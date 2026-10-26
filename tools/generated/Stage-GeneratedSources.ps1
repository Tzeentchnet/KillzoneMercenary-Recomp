# SPDX-License-Identifier: GPL-2.0-or-later
# Adapted from tools/stage-aot-sources.ps1 in the verified prior AOT snapshot.

<#
.SYNOPSIS
    Synchronizes immutable generated sources into a stable build input tree.

.DESCRIPTION
    Copies files only when their content changes, preserving the timestamps of
    byte-identical files so incremental builds can reuse their object files.
    Files managed by an earlier invocation but absent from the new source are
    removed. Unmanaged target files are never deleted.

    The source is fully enumerated, hashed, and checked for required files
    before the target is modified. Source and target must be explicit,
    non-overlapping paths; this script has no machine-specific defaults.
    The optional provenance parameter set validates Gate 1 provenance before
    any target modification. Omitting it preserves the legacy staging mode.

.PARAMETER SourceDir
    An immutable generator-output directory.

.PARAMETER TargetDir
    The stable staging directory consumed by the build.

.PARAMETER RequiredFile
    Optional source-relative paths that must exist before synchronization.

.PARAMETER RequiredProvenance
    Opt-in source-relative provenance file. When supplied, RuntimeManifest is
    also mandatory and the provenance validator must accept the complete
    source inventory before staging starts.

.PARAMETER RuntimeManifest
    Raw runtime manifest used to revalidate RequiredProvenance.

.EXAMPLE
    .\tools\generated\Stage-GeneratedSources.ps1 `
        -SourceDir .\out\generated-v2 `
        -TargetDir .\out\generated-stable `
        -RequiredFile generated_registry.c

.EXAMPLE
    .\tools\generated\Stage-GeneratedSources.ps1 `
        -SourceDir .\out\generated-v2 `
        -TargetDir .\out\generated-stable `
        -RequiredProvenance .generated-source-provenance.json `
        -RuntimeManifest .\config\local\runtime-manifest.json
#>
[CmdletBinding(DefaultParameterSetName = 'Legacy')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $SourceDir,

    [Parameter(Mandatory = $true, Position = 1)]
    [string] $TargetDir,

    [string[]] $RequiredFile = @(),

    [Parameter(Mandatory = $true, ParameterSetName = 'Provenance')]
    [Alias('ProvenanceFile', 'RequiredProvenanceFile')]
    [string] $RequiredProvenance,

    [Parameter(Mandatory = $true, ParameterSetName = 'Provenance')]
    [string] $RuntimeManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestName = '.generated-source-manifest.json'

function Get-NormalizedFullPath {
    param([string] $Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-PathAtOrBelow {
    param(
        [string] $Candidate,
        [string] $Root
    )

    if ($Candidate.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $Candidate.StartsWith(
        $Root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Get-RelativePath {
    param(
        [string] $Root,
        [string] $Path
    )

    $rootWithSeparator = $Root + [IO.Path]::DirectorySeparatorChar
    $rootUri = New-Object Uri($rootWithSeparator)
    $pathUri = New-Object Uri($Path)
    return [Uri]::UnescapeDataString(
        $rootUri.MakeRelativeUri($pathUri).ToString()
    ).Replace('\', '/')
}

function ConvertTo-SafeRelativePath {
    param([string] $Path)

    $normalized = $Path.Trim().Replace('\', '/')
    if (
        [string]::IsNullOrWhiteSpace($normalized) -or
        $normalized.Contains(':') -or
        $normalized.Contains('//') -or
        [IO.Path]::IsPathRooted($normalized) -or
        $normalized -eq '.' -or
        $normalized.StartsWith('./', [StringComparison]::Ordinal) -or
        $normalized.Contains('/./') -or
        $normalized.EndsWith('/.', [StringComparison]::Ordinal) -or
        $normalized -eq '..' -or
        $normalized.StartsWith('../', [StringComparison]::Ordinal) -or
        $normalized.Contains('/../') -or
        $normalized.EndsWith('/..', [StringComparison]::Ordinal)
    ) {
        throw 'Generated-source staging: unsafe source-relative path.'
    }

    return $normalized
}

function Get-Sha256 {
    param([string] $Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBom {
    param(
        [string] $Path,
        [string] $Content
    )

    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
    throw 'Generated-source staging: source does not exist or is not a directory.'
}

$source = Get-NormalizedFullPath -Path (Resolve-Path -LiteralPath $SourceDir).ProviderPath
$target = Get-NormalizedFullPath -Path $TargetDir

if (
    (Test-PathAtOrBelow -Candidate $source -Root $target) -or
    (Test-PathAtOrBelow -Candidate $target -Root $source)
) {
    throw 'Generated-source staging: source and target directories must not overlap.'
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath $source -File -Recurse -Force |
        Where-Object { $_.Name -cne $manifestName }
)
if ($sourceFiles.Count -eq 0) {
    throw 'Generated-source staging: source is empty.'
}

$entries = New-Object System.Collections.Generic.List[object]
$sourcePaths = New-Object 'System.Collections.Generic.HashSet[string]' (
    [StringComparer]::OrdinalIgnoreCase
)
$sourceByPath = New-Object (
    'System.Collections.Generic.Dictionary[string, System.IO.FileInfo]'
) ([StringComparer]::Ordinal)
foreach ($file in $sourceFiles) {
    $relative = ConvertTo-SafeRelativePath (
        Get-RelativePath -Root $source -Path $file.FullName
    )
    if (-not $sourcePaths.Add($relative)) {
        throw 'Generated-source staging: source contains case-colliding paths.'
    }
    $sourceByPath.Add($relative, $file)
}
$sortedSourcePaths = [string[]] @($sourceByPath.Keys)
[Array]::Sort($sortedSourcePaths, [StringComparer]::Ordinal)
foreach ($relative in $sortedSourcePaths) {
    $file = $sourceByPath[$relative]
    $entries.Add([pscustomobject][ordered]@{
        path = $relative
        sha256 = Get-Sha256 -Path $file.FullName
        source = $file.FullName
    })
}

foreach ($required in $RequiredFile) {
    $requiredPath = ConvertTo-SafeRelativePath -Path $required
    if (-not $sourcePaths.Contains($requiredPath)) {
        throw 'Generated-source staging: a required file is missing; target was not modified.'
    }
}

$provenancePath = $null
if ($PSCmdlet.ParameterSetName -ceq 'Provenance') {
    $provenancePath = ConvertTo-SafeRelativePath -Path $RequiredProvenance
    if ($RequiredProvenance -cne $provenancePath -or
        -not $sourcePaths.Contains($provenancePath)) {
        throw (
            'Generated-source staging: required provenance is missing or ' +
            'not a normalized forward-slash source-relative path; target ' +
            'was not modified.'
        )
    }
    $validator = Join-Path $PSScriptRoot 'Test-GeneratedSourceProvenance.ps1'
    & $validator `
        -ProvenanceFile (
            Join-Path $source $provenancePath.Replace('/', '\')
        ) `
        -SourceRoot $source `
        -RuntimeManifest $RuntimeManifest `
        -RepositoryRoot ([IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '..\..')
        )) `
        -Quiet
}

$targetExists = Test-Path -LiteralPath $target
if (Test-Path -LiteralPath $target) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw 'Generated-source staging: target exists and is not a directory.'
    }
}

$manifestPath = Join-Path $target $manifestName
$previousPaths = New-Object System.Collections.Generic.List[string]
$previousPathSet = New-Object 'System.Collections.Generic.HashSet[string]' (
    [StringComparer]::OrdinalIgnoreCase
)
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $previous = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($previous.schemaVersion -ne 1) {
            throw "unsupported schema version '$($previous.schemaVersion)'"
        }
        foreach ($entry in @($previous.files)) {
            $previousPath = ConvertTo-SafeRelativePath -Path ([string] $entry.path)
            if ($previousPath -ceq $manifestName -or
                -not $previousPathSet.Add($previousPath)) {
                throw 'duplicate or reserved managed path'
            }
            $previousPaths.Add($previousPath)
        }
    } catch {
        throw 'Generated-source staging: invalid target manifest; target was not modified.'
    }
}

# Preflight every destination before copying any file.
foreach ($entry in $entries) {
    $destination = Join-Path $target ($entry.path.Replace('/', '\'))
    if (Test-Path -LiteralPath $destination -PathType Container) {
        throw 'Generated-source staging: a managed destination is a directory.'
    }
}

if (-not $targetExists) {
    New-Item -ItemType Directory -Path $target | Out-Null
}

$copied = 0
$unchanged = 0
foreach ($entry in $entries) {
    $destination = Join-Path $target ($entry.path.Replace('/', '\'))
    $destinationDirectory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    if (
        (Test-Path -LiteralPath $destination -PathType Leaf) -and
        (Get-Sha256 -Path $destination) -ceq $entry.sha256
    ) {
        Write-Verbose 'A managed file is unchanged.'
        $unchanged++
        continue
    }

    Write-Verbose 'Copying a changed managed file.'
    Copy-Item -LiteralPath $entry.source -Destination $destination -Force
    (Get-Item -LiteralPath $destination).LastWriteTimeUtc = [DateTime]::UtcNow
    if ((Get-Sha256 -Path $destination) -cne $entry.sha256) {
        throw 'Generated-source staging: copy verification failed.'
    }
    $copied++
}

$removed = 0
foreach ($relative in $previousPaths) {
    if ($sourcePaths.Contains($relative)) {
        continue
    }

    $stalePath = Join-Path $target ($relative.Replace('/', '\'))
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
        Write-Verbose 'Removing a stale managed file.'
        Remove-Item -LiteralPath $stalePath -Force
        $removed++
    }
}

$manifestFiles = @(
    $entries | ForEach-Object {
        [pscustomobject][ordered]@{
            path = $_.path
            sha256 = $_.sha256
        }
    }
)
$manifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    files = $manifestFiles
}
$manifestText = ($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine
$oldManifestText = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    Get-Content -LiteralPath $manifestPath -Raw
} else {
    $null
}
if ($oldManifestText -cne $manifestText) {
    Write-Utf8NoBom -Path $manifestPath -Content $manifestText
}

Write-Host (
    "Generated-source staging: $copied copied, $unchanged unchanged, " +
    "$removed stale managed file(s) removed."
)
