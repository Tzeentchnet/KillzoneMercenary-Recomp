# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ArchivePath,

    [Parameter(Mandatory = $true)]
    [string] $Vita3KExecutable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{7,40}$')]
    [string] $Vita3KSourceRevision,

    [Parameter(Mandatory = $true)]
    [string] $PrivateDataRoot,

    [string] $ArmrecompExecutable,

    [ValidateSet('All', 'Install', 'Dump')]
    [string] $Phase = 'All',

    [switch] $DryRun,

    [switch] $Redact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$titleId = 'PCSA00107'
$inspector = Join-Path $PSScriptRoot 'Inspect-KillzoneDump.ps1'
$manifestBuilder = Join-Path $PSScriptRoot 'New-KillzoneElfManifest.ps1'
$normalizer = Join-Path `
    $PSScriptRoot `
    'Normalize-KillzoneRuntimeImages.ps1'

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
                "Private data root is inside a Git repository but is not ignored: " +
                "'$Root'."
            )
        }
    }
}

function Read-FilePrefix {
    param(
        [string] $Path,
        [int] $Count
    )

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    try {
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -ne $Count) {
            throw "File is shorter than the required $Count-byte signature."
        }
        return $buffer
    } finally {
        $stream.Dispose()
    }
}

function Test-BytePrefix {
    param(
        [byte[]] $Actual,
        [byte[]] $Expected
    )

    if ($Actual.Count -lt $Expected.Count) {
        return $false
    }
    for ($index = 0; $index -lt $Expected.Count; ++$index) {
        if ($Actual[$index] -ne $Expected[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-InstalledContent {
    param([string] $PortableRoot)

    $installedRoot = Join-Path `
        $PortableRoot `
        "fs\ux0\app\$titleId"
    $installedEboot = Join-Path $installedRoot 'eboot.bin'
    $installedGameData = Join-Path `
        $installedRoot `
        'game_data\data_ngp.psarc'

    if (-not (Test-Path -LiteralPath $installedEboot -PathType Leaf)) {
        throw (
            "Vita3K installation did not produce '$titleId/eboot.bin' " +
            'inside the private portable data root.'
        )
    }
    if (-not (Test-Path -LiteralPath $installedGameData -PathType Leaf)) {
        throw (
            "Vita3K installation did not produce the required PSARC " +
            'inside the private portable data root.'
        )
    }

    $ebootPrefix = Read-FilePrefix -Path $installedEboot -Count 4
    $isSelf = Test-BytePrefix `
        $ebootPrefix `
        ([byte[]] @(0x53, 0x43, 0x45, 0x00))
    $isElf = Test-BytePrefix `
        $ebootPrefix `
        ([byte[]] @(0x7f, 0x45, 0x4c, 0x46))
    if (-not $isSelf -and -not $isElf) {
        throw (
            'Installed eboot.bin is still PFS-protected or has an ' +
            'unrecognized SELF/ELF signature.'
        )
    }

    $gameDataPrefix = Read-FilePrefix -Path $installedGameData -Count 4
    if (-not (Test-BytePrefix `
            $gameDataPrefix `
            ([Text.Encoding]::ASCII.GetBytes('PSAR')))) {
        throw (
            'Installed data_ngp.psarc is still PFS-protected or does not ' +
            'have PSARC magic.'
        )
    }

    return [ordered]@{
        root = $installedRoot
        ebootState = if ($isSelf) { 'self' } else { 'elf' }
        gameDataState = 'psarc'
    }
}

function ConvertTo-NativeArgument {
    param([string] $Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            ++$backslashes
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append('\' * ($backslashes * 2 + 1))
            $null = $builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            $null = $builder.Append('\' * $backslashes)
            $backslashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) {
        $null = $builder.Append('\' * ($backslashes * 2))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function New-NativeProcessStartInfo {
    param(
        [string] $Executable,
        [string[]] $Arguments,
        [string] $WorkingDirectory,
        [bool] $RedirectOutput
    )

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $isCommandScript = [IO.Path]::GetExtension($Executable) -in @(
        '.bat',
        '.cmd'
    )
    if ($isCommandScript) {
        $startInfo.FileName = $env:ComSpec
        $commandArguments = @(
            '/d'
            '/s'
            '/c'
            (
                (ConvertTo-NativeArgument $Executable) + ' ' +
                (($Arguments | ForEach-Object {
                    ConvertTo-NativeArgument $_
                }) -join ' ')
            )
        )
    } else {
        $startInfo.FileName = $Executable
        $commandArguments = @($Arguments)
    }

    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $RedirectOutput
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $RedirectOutput
    $startInfo.RedirectStandardError = $RedirectOutput

    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $commandArguments) {
            $startInfo.ArgumentList.Add($argument)
        }
    } else {
        $startInfo.Arguments = (
            $commandArguments |
                ForEach-Object { ConvertTo-NativeArgument $_ }
        ) -join ' '
    }
    return $startInfo
}

function Invoke-CapabilityProbe {
    param(
        [string] $Executable,
        [string] $WorkingDirectory
    )

    $startInfo = New-NativeProcessStartInfo `
        -Executable $Executable `
        -Arguments @('--help') `
        -WorkingDirectory $WorkingDirectory `
        -RedirectOutput $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Unable to start Vita3K capability probe.'
        }
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = @($standardOutput, $standardError) -join "`n"
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-Vita3K {
    param(
        [string] $Executable,
        [string[]] $Arguments,
        [string] $WorkingDirectory
    )

    $startInfo = New-NativeProcessStartInfo `
        -Executable $Executable `
        -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -RedirectOutput $false
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Unable to start Vita3K.'
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }
    if ($exitCode -ne 0) {
        throw "Vita3K exited with code $exitCode."
    }
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

$archive = [IO.Path]::GetFullPath($ArchivePath)
$vita3k = [IO.Path]::GetFullPath($Vita3KExecutable)
$privateRoot = [IO.Path]::GetFullPath($PrivateDataRoot)
$armrecomp = $null
if ($Phase -in @('All', 'Dump')) {
    if ([string]::IsNullOrWhiteSpace($ArmrecompExecutable)) {
        throw 'Dump and All phases require -ArmrecompExecutable.'
    }
    $armrecomp = [IO.Path]::GetFullPath($ArmrecompExecutable)
    if (-not (Test-Path -LiteralPath $armrecomp -PathType Leaf)) {
        throw "armrecomp executable does not exist: '$armrecomp'."
    }
}

if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Archive does not exist: '$archive'."
}
if (-not $archive.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The external Vita3K workflow currently accepts ZIP archives only.'
}
if (-not (Test-Path -LiteralPath $vita3k -PathType Leaf)) {
    throw "Vita3K executable does not exist: '$vita3k'."
}
Assert-PrivateRoot -Root $privateRoot
if (-not (Test-PathWithinRoot -Candidate $vita3k -Root $privateRoot)) {
    throw (
        'Vita3K executable must be staged inside the explicit private data ' +
        'root so that portable-mode writes cannot reach the repository.'
    )
}

$vita3kItem = Get-Item -LiteralPath $vita3k -Force
if (($vita3kItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Vita3K executable must not be a reparse point.'
}

$vita3kDirectory = Split-Path -Parent $vita3k
$portableRoot = Join-Path $vita3kDirectory 'portable'
if (-not (Test-Path -LiteralPath $portableRoot -PathType Container)) {
    throw (
        "Vita3K portable directory is missing: '$portableRoot'. Create it " +
        'before running this workflow.'
    )
}
if (-not (Test-PathWithinRoot -Candidate $portableRoot -Root $privateRoot)) {
    throw 'Vita3K portable directory must be inside the private data root.'
}

$inspectionJson = & $inspector `
    -ArchivePath $archive `
    -OutputFormat Json `
    -Redact
$inspection = $inspectionJson | ConvertFrom-Json
if (-not $inspection.valid) {
    throw 'Archive inspection did not produce a valid PCSA00107 layout.'
}

$capability = Invoke-CapabilityProbe `
    -Executable $vita3k `
    -WorkingDirectory $privateRoot
if ($capability.ExitCode -ne 0) {
    throw (
        "Vita3K capability probe failed with exit code " +
        "$($capability.ExitCode)."
    )
}
if ($capability.Output -notmatch '(?m)(^|\s)--dump-elfs(?:[,\s]|$)') {
    throw (
        "Vita3K dump capability is unavailable. The executable's --help " +
        'output does not advertise --dump-elfs.'
    )
}

$installArguments = @(
    $archive
    '--frontend'
    'qt'
)
$dumpArguments = @(
    '--installed-path'
    $titleId
    '--dump-elfs'
    '--frontend'
    'sdl'
)

$plannedCommands = New-Object System.Collections.Generic.List[object]
if ($Phase -in @('All', 'Install')) {
    $plannedCommands.Add([ordered]@{
        phase = 'install'
        executable = Get-ReportedPath $vita3k '<private-vita3k-executable>'
        arguments = @(
            Get-ReportedPath $archive '<private-source-archive>'
            '--frontend'
            'qt'
        )
    })
}
if ($Phase -in @('All', 'Dump')) {
    $plannedCommands.Add([ordered]@{
        phase = 'dump'
        executable = Get-ReportedPath $vita3k '<private-vita3k-executable>'
        arguments = @($dumpArguments)
    })
    $plannedCommands.Add([ordered]@{
        phase = 'normalize'
        executable = Get-ReportedPath $armrecomp '<armrecomp-executable>'
        arguments = @(
            'normalize'
            '<private-raw-runtime-image>'
            '<private-normalized-runtime-image>'
        )
    })
}

$dumpRoot = Join-Path $portableRoot "elfdumps\$titleId"
$normalizedRoot = Join-Path $privateRoot "runtime-images\$titleId"
$manifestPath = Join-Path `
    $privateRoot `
    "manifests\$titleId.runtime-images.json"

if ($DryRun) {
    $dryRunReport = [ordered]@{
        schemaVersion = 1
        dryRun = $true
        titleId = $titleId
        phase = $Phase.ToLowerInvariant()
        vita3kSourceRevision = $Vita3KSourceRevision.ToLowerInvariant()
        privateDataRoot = Get-ReportedPath `
            $privateRoot `
            '<private-data-root>'
        portableDataRoot = Get-ReportedPath `
            $portableRoot `
            '<private-portable-data-root>'
        expectedRawDumpRoot = Get-ReportedPath `
            $dumpRoot `
            '<private-raw-elf-root>'
        expectedRuntimeImageRoot = Get-ReportedPath `
            $normalizedRoot `
            '<private-normalized-elf-root>'
        expectedManifest = Get-ReportedPath `
            $manifestPath `
            '<private-manifest-path>'
        commands = $plannedCommands.ToArray()
    }
    $json = $dryRunReport | ConvertTo-Json -Depth 10
    Write-Output ($json -replace "`r`n", "`n")
    return
}

if ($Phase -in @('All', 'Install')) {
    Invoke-Vita3K `
        -Executable $vita3k `
        -Arguments $installArguments `
        -WorkingDirectory $privateRoot
}

$installedState = Assert-InstalledContent -PortableRoot $portableRoot
if ($Phase -in @('All', 'Dump')) {
    $existingDumps = @()
    if (Test-Path -LiteralPath $dumpRoot -PathType Container) {
        $existingDumps = @(
            Get-ChildItem `
                -LiteralPath $dumpRoot `
                -File `
                -Recurse `
                -Filter '*.elf'
        )
    }
    if ($existingDumps.Count -gt 0) {
        throw (
            "The private dump directory already contains ELF files: " +
            "'$dumpRoot'. Move or remove that directory before dumping so " +
            'stale images cannot enter the manifest.'
        )
    }

    Invoke-Vita3K `
        -Executable $vita3k `
        -Arguments $dumpArguments `
        -WorkingDirectory $privateRoot

    if (-not (Test-Path -LiteralPath $dumpRoot -PathType Container)) {
        throw (
            'Vita3K exited without creating the expected post-link ELF ' +
            "dump directory: '$dumpRoot'."
        )
    }
    if (@(Get-ChildItem -LiteralPath $dumpRoot -File -Recurse -Filter '*.elf').
        Count -eq 0) {
        throw (
            'Vita3K exited without producing any post-link ELF dumps. ' +
            'Dump capability is present but did not capture the title.'
        )
    }

    $archiveHash = (
        Get-FileHash -LiteralPath $archive -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $normalizationJson = & $normalizer `
        -PrivateDataRoot $privateRoot `
        -DumpRoot $dumpRoot `
        -NormalizedRoot $normalizedRoot `
        -ArmrecompExecutable $armrecomp `
        -Redact:$Redact
    $normalization = $normalizationJson | ConvertFrom-Json
    $writtenManifest = & $manifestBuilder `
        -PrivateDataRoot $privateRoot `
        -DumpRoot $normalizedRoot `
        -ManifestPath $manifestPath `
        -SourceArchivePath $archive `
        -SourceArchiveSha256 $archiveHash `
        -Vita3KSourceRevision $Vita3KSourceRevision `
        -TitleId $titleId
} else {
    $writtenManifest = $null
    $normalization = $null
}

$result = [ordered]@{
    schemaVersion = 1
    dryRun = $false
    titleId = $titleId
    phase = $Phase.ToLowerInvariant()
    installed = $installedState
    rawDumpRoot = if ($null -ne $writtenManifest) { $dumpRoot } else { $null }
    dumpRoot = if ($null -ne $writtenManifest) {
        $normalizedRoot
    } else {
        $null
    }
    normalization = $normalization
    manifest = $writtenManifest
}
$resultJson = $result | ConvertTo-Json -Depth 10
Write-Output ($resultJson -replace "`r`n", "`n")
