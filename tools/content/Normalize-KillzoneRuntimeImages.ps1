# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PrivateDataRoot,

    [Parameter(Mandatory = $true)]
    [string] $DumpRoot,

    [Parameter(Mandatory = $true)]
    [string] $NormalizedRoot,

    [Parameter(Mandatory = $true)]
    [string] $ArmrecompExecutable,

    [switch] $Redact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PathWithinRoot {
    param(
        [string] $Candidate,
        [string] $Root
    )

    $fullCandidate = [IO.Path]::GetFullPath($Candidate).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if ($fullCandidate.Equals(
            $fullRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $true
    }
    return $fullCandidate.StartsWith(
        $fullRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-PrivateRoot {
    param([string] $Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Private data root does not exist: '$Root'."
    }
    $rootItem = Get-Item -LiteralPath $Root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Private data root must not be a reparse point.'
    }

    $gitRootOutput = @(
        & git -C $Root rev-parse --show-toplevel 2>$null
    )
    if ($LASTEXITCODE -eq 0 -and $gitRootOutput.Count -gt 0) {
        $gitRoot = [IO.Path]::GetFullPath($gitRootOutput[0])
        if ([IO.Path]::GetFullPath($Root).TrimEnd('\') -eq
            $gitRoot.TrimEnd('\')) {
            throw 'The repository root cannot be used as the private data root.'
        }

        $relative = [IO.Path]::GetFullPath($Root).Substring(
            $gitRoot.TrimEnd('\').Length
        ).TrimStart('\').Replace('\', '/')
        & git -C $gitRoot check-ignore -q -- $relative 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw (
                "Private data root is inside a Git repository but is not " +
                "ignored: '$Root'."
            )
        }
    }
}

function Get-RelativeNormalizedPath {
    param(
        [string] $Path,
        [string] $Root
    )

    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Path is outside dump root: '$fullPath'."
    }
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-OrdinallySortedStrings {
    param([string[]] $Values)

    $result = @($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function Get-ReportedPath {
    param(
        [string] $Path,
        [string] $Placeholder
    )

    if ($Redact) {
        return $Placeholder
    }
    return $Path
}

function Read-NormalizationSummary {
    param(
        [object[]] $Output,
        [string] $RelativePath
    )

    $text = (@($Output | ForEach-Object { "$_" }) -join "`n")
    if ($text -notmatch (
            '(?m)^normalized ([0-9]+) relocations? across ' +
            '([0-9]+) streams?\r?$'
        )) {
        throw "Normalizer returned an invalid summary for '$RelativePath'."
    }
    $records = [UInt64] $Matches[1]
    $streams = [UInt64] $Matches[2]
    if ($text -notmatch '(?m)^  changed       ([0-9]+)\r?$') {
        throw "Normalizer omitted the changed count for '$RelativePath'."
    }
    $changed = [UInt64] $Matches[1]
    if ($text -notmatch '(?m)^  preserved     ([0-9]+)\r?$') {
        throw "Normalizer omitted the preserved count for '$RelativePath'."
    }
    $preserved = [UInt64] $Matches[1]
    if ($text -notmatch '(?m)^  unsupported   ([0-9]+)\r?$') {
        throw "Normalizer omitted the unsupported count for '$RelativePath'."
    }
    $unsupported = [UInt64] $Matches[1]
    if ($text -notmatch '(?m)^  outside file  ([0-9]+)\r?$') {
        throw "Normalizer omitted the outside-file count for '$RelativePath'."
    }
    $outside = [UInt64] $Matches[1]
    if ($unsupported -ne 0 -or $outside -ne 0) {
        throw (
            "Normalizer reported unsupported or out-of-file records for " +
            "'$RelativePath'."
        )
    }
    return [pscustomobject]@{
        Records = $records
        Streams = $streams
        Changed = $changed
        Preserved = $preserved
    }
}

$privateRoot = [IO.Path]::GetFullPath($PrivateDataRoot)
$dumpDirectory = [IO.Path]::GetFullPath($DumpRoot)
$normalizedDirectory = [IO.Path]::GetFullPath($NormalizedRoot)
$armrecomp = [IO.Path]::GetFullPath($ArmrecompExecutable)

Assert-PrivateRoot -Root $privateRoot
if (-not (Test-PathWithinRoot -Candidate $dumpDirectory -Root $privateRoot)) {
    throw 'Dump root must be inside the explicit private data root.'
}
if (-not (Test-PathWithinRoot `
        -Candidate $normalizedDirectory `
        -Root $privateRoot)) {
    throw 'Normalized root must be inside the explicit private data root.'
}
if ($dumpDirectory.Equals(
        $normalizedDirectory,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'Raw dump and normalized roots must differ.'
}
if (-not (Test-Path -LiteralPath $dumpDirectory -PathType Container)) {
    throw "ELF dump root does not exist: '$dumpDirectory'."
}
if (Test-Path -LiteralPath $normalizedDirectory) {
    throw 'Normalized root must not already exist.'
}
if (-not (Test-Path -LiteralPath $armrecomp -PathType Leaf)) {
    throw "armrecomp executable does not exist: '$armrecomp'."
}

$dumpItem = Get-Item -LiteralPath $dumpDirectory -Force
if (($dumpItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'ELF dump root must not be a reparse point.'
}

$pathToFile = @{}
$relativePaths = New-Object System.Collections.Generic.List[string]
foreach (
    $file in Get-ChildItem `
        -LiteralPath $dumpDirectory `
        -File `
        -Recurse `
        -Filter '*.elf'
) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "ELF input must not be a reparse point: '$($file.FullName)'."
    }
    $relativePath = Get-RelativeNormalizedPath `
        -Path $file.FullName `
        -Root $dumpDirectory
    if ($pathToFile.ContainsKey($relativePath)) {
        throw "Duplicate relative ELF path: '$relativePath'."
    }
    $pathToFile.Add($relativePath, $file.FullName)
    $relativePaths.Add($relativePath)
}

$orderedPaths = Get-OrdinallySortedStrings $relativePaths.ToArray()
if ($orderedPaths.Count -eq 0) {
    throw "No ELF dumps were found below '$dumpDirectory'."
}

$createdRoot = $false
try {
    [IO.Directory]::CreateDirectory($normalizedDirectory) | Out-Null
    $createdRoot = $true
    $modules = New-Object System.Collections.Generic.List[object]
    [UInt64] $recordCount = 0
    [UInt64] $streamCount = 0
    [UInt64] $changedCount = 0
    [UInt64] $preservedCount = 0

    foreach ($relativePath in $orderedPaths) {
        $sourcePath = $pathToFile[$relativePath]
        $destinationPath = Join-Path `
            $normalizedDirectory `
            ($relativePath.Replace('/', '\'))
        [IO.Directory]::CreateDirectory(
            (Split-Path -Parent $destinationPath)
        ) | Out-Null
        $sourceHashBefore = (
            Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256
        ).Hash
        $savedErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $toolOutput = @(
                & $armrecomp normalize $sourcePath $destinationPath 2>&1
            )
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
        if ($exitCode -ne 0) {
            $diagnostic = (@(
                $toolOutput | ForEach-Object { "$_" }
            ) -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($diagnostic)) {
                $diagnostic = 'no diagnostic'
            }
            throw (
                "Normalization failed for '$relativePath' with exit code " +
                "$exitCode`: $diagnostic"
            )
        }
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Normalizer did not create '$relativePath'."
        }
        $sourceHashAfter = (
            Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256
        ).Hash
        if ($sourceHashBefore -cne $sourceHashAfter) {
            throw "Normalizer changed raw input '$relativePath'."
        }
        $sourceLength = (Get-Item -LiteralPath $sourcePath).Length
        $destinationLength = (
            Get-Item -LiteralPath $destinationPath
        ).Length
        if ($sourceLength -ne $destinationLength) {
            throw "Normalized ELF size changed for '$relativePath'."
        }
        $summary = Read-NormalizationSummary `
            -Output $toolOutput `
            -RelativePath $relativePath
        $recordCount += $summary.Records
        $streamCount += $summary.Streams
        $changedCount += $summary.Changed
        $preservedCount += $summary.Preserved
        $modules.Add([ordered]@{
            path = $relativePath
            relocationRecords = $summary.Records
            relocationStreams = $summary.Streams
            changedRecords = $summary.Changed
            preservedPostLinkRecords = $summary.Preserved
        })
    }

    $outputPaths = @(
        Get-ChildItem `
            -LiteralPath $normalizedDirectory `
            -File `
            -Recurse |
            ForEach-Object {
                Get-RelativeNormalizedPath `
                    -Path $_.FullName `
                    -Root $normalizedDirectory
            }
    )
    $orderedOutputPaths = Get-OrdinallySortedStrings $outputPaths
    if ($orderedOutputPaths.Count -ne $orderedPaths.Count) {
        throw 'Normalized output file count does not match the raw ELF set.'
    }
    for ($index = 0; $index -lt $orderedPaths.Count; ++$index) {
        if ($orderedPaths[$index] -cne $orderedOutputPaths[$index]) {
            throw 'Normalized output paths do not match the raw ELF set.'
        }
    }

    $report = [ordered]@{
        schemaVersion = 1
        rawDumpRoot = Get-ReportedPath `
            $dumpDirectory `
            '<private-raw-elf-root>'
        normalizedRoot = Get-ReportedPath `
            $normalizedDirectory `
            '<private-normalized-elf-root>'
        moduleCount = $modules.Count
        relocationRecords = $recordCount
        relocationStreams = $streamCount
        changedRecords = $changedCount
        preservedPostLinkRecords = $preservedCount
        unsupportedRecords = 0
        outsideFileRecords = 0
        modules = $modules.ToArray()
    }
    $json = $report | ConvertTo-Json -Depth 8
    Write-Output ($json -replace "`r`n", "`n")
} catch {
    if ($createdRoot -and
        (Test-Path -LiteralPath $normalizedDirectory -PathType Container)) {
        Remove-Item -LiteralPath $normalizedDirectory -Recurse -Force
    }
    throw
}
