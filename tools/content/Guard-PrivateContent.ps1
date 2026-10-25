# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string[]] $Paths,
    [string] $PrivateRootsFile,
    [string[]] $PrivateRoot = @(),
    [switch] $Tracked,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    param([string] $RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return [IO.Path]::GetFullPath($RequestedRoot)
    }

    $detectedRoot = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($detectedRoot)) {
        throw 'Unable to locate a Git repository. Pass -RepositoryRoot explicitly.'
    }

    return [IO.Path]::GetFullPath(($detectedRoot | Select-Object -First 1))
}

function Get-StagedPaths {
    param([string] $Root)

    $git = Get-Command git -ErrorAction Stop
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $git.Source
    $startInfo.WorkingDirectory = $Root
    $startInfo.Arguments =
        '-c core.quotepath=false diff --cached --name-only --diff-filter=ACMR -z --'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Unable to start Git while reading staged paths.'
    }

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "Git failed while reading staged paths: $($standardError.Trim())"
    }

    return $standardOutput.Split(
        @([char] 0),
        [StringSplitOptions]::RemoveEmptyEntries
    )
}

function Get-TrackedPaths {
    param([string] $Root)

    $git = Get-Command git -ErrorAction Stop
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $git.Source
    $startInfo.WorkingDirectory = $Root
    $startInfo.Arguments = '-c core.quotepath=false ls-files -z --'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Unable to start Git while reading tracked paths.'
    }

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "Git failed while reading tracked paths: $($standardError.Trim())"
    }

    return $standardOutput.Split(
        @([char] 0),
        [StringSplitOptions]::RemoveEmptyEntries
    )
}

function ConvertTo-RepositoryPath {
    param([string] $Path)

    $normalized = $Path.Trim().Replace('\', '/')
    while ($normalized.StartsWith('./', [StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }

    return $normalized
}

function Get-ConfiguredPrivateRoots {
    param(
        [string] $Root,
        [string] $RequestedFile,
        [string[]] $AdditionalRoots
    )

    $rootSpecs = New-Object System.Collections.Generic.List[string]
    foreach ($additionalRoot in $AdditionalRoots) {
        if (-not [string]::IsNullOrWhiteSpace($additionalRoot)) {
            $rootSpecs.Add($additionalRoot.Trim())
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:KZM_RECOMP_PRIVATE_ROOTS)) {
        foreach ($environmentRoot in
            $env:KZM_RECOMP_PRIVATE_ROOTS.Split([IO.Path]::PathSeparator)) {
            if (-not [string]::IsNullOrWhiteSpace($environmentRoot)) {
                $rootSpecs.Add($environmentRoot.Trim())
            }
        }
    }

    $rootsFile = $RequestedFile
    if ([string]::IsNullOrWhiteSpace($rootsFile)) {
        $rootsFile = Join-Path $Root 'config\private-roots.txt'
    } elseif (-not [IO.Path]::IsPathRooted($rootsFile)) {
        $rootsFile = Join-Path $Root $rootsFile
    }

    if (Test-Path -LiteralPath $rootsFile -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $rootsFile) {
            $candidate = $line.Trim()
            if ($candidate.Length -gt 0 -and -not $candidate.StartsWith('#')) {
                $rootSpecs.Add($candidate)
            }
        }
    }

    $resolvedRoots = New-Object System.Collections.Generic.List[string]
    foreach ($rootSpec in $rootSpecs) {
        $expandedRoot = [Environment]::ExpandEnvironmentVariables($rootSpec)
        if (-not [IO.Path]::IsPathRooted($expandedRoot)) {
            $expandedRoot = Join-Path $Root $expandedRoot
        }

        $fullRoot = [IO.Path]::GetFullPath($expandedRoot).TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        if (-not $resolvedRoots.Contains($fullRoot)) {
            $resolvedRoots.Add($fullRoot)
        }
    }

    return $resolvedRoots
}

function Test-PathWithinRoot {
    param(
        [string] $Candidate,
        [string] $Root
    )

    if ($Candidate.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = $Root + [IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith(
        $rootPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )
}

$repository = Get-RepositoryRoot -RequestedRoot $RepositoryRoot
$configuredRoots = @(
    Get-ConfiguredPrivateRoots `
        -Root $repository `
        -RequestedFile $PrivateRootsFile `
        -AdditionalRoots $PrivateRoot
)

$rules = @(
    [pscustomobject]@{
        Id = 'known-title-content'
        Pattern = '(?:^|/)(?:app|addcont|patch)/PCSA00107(?:/|$)|' +
            '(?:^|/)license/(?:app|addcont)/PCSA00107(?:/|$)|' +
            '(?:^|/)PCSA00107(?:/|$)|' +
            '(?:PCSA00107|killzone[ ._-]*mercenary)[^/]*\.' +
            '(?:zip|7z|rar|vpk|pkg)$'
        Reason = 'known PCSA00107 retail archive or title-data path'
    }
    [pscustomobject]@{
        Id = 'retail-data'
        Pattern = '(?:^|/)(?:eboot\.bin|work\.bin)$|' +
            '(?:^|/)(?:sce_module|sce_sys/package|game_data)(?:/|$)|' +
            '\.(?:self|elf|suprx|psarc|vpk|pkg)$'
        Reason = 'retail module, archive, or installed game data'
    }
    [pscustomobject]@{
        Id = 'key-or-license'
        Pattern = '\.(?:rif|rap|key|keys|pem|p12|pfx|keystore)$|' +
            '(?:^|/)(?:klicensee|zrif|keys?\.bin)(?:\.txt)?$|' +
            '(?:^|/)(?:ux0/)?license/(?:app|addcont)(?:/|$)|' +
            '(?:^|/)nonpdrm/(?:licenses?|keys?)(?:/|$)'
        Reason = 'key, credential, or retail-license material'
    }
    [pscustomobject]@{
        Id = 'extracted-assets'
        Pattern = '^(?:assets-extracted|extracted-assets|game-assets|' +
            'title-assets|extracted|decrypted|dumps)(?:/|$)'
        Reason = 'extracted or decrypted title asset root'
    }
    [pscustomobject]@{
        Id = 'generated-title-code'
        Pattern = '^(?:generated|generated-title|recompiled|' +
            'recomp-output)(?:/|$)|' +
            '(?:^|/)src/game/(?:generated|recompiled)(?:/|$)'
        Reason = 'locally generated title code'
    }
    [pscustomobject]@{
        Id = 'trace-or-capture'
        Pattern = '^(?:trace|traces|capture|captures)(?:/|$)|' +
            '\.(?:trace|vktrace|rdc|pix3|wpix|pcap|pcapng|etl|' +
            'nsys-rep|qdrep)$'
        Reason = 'execution trace or graphics/network capture'
    }
    [pscustomobject]@{
        Id = 'shader-cache'
        Pattern = '(?:^|/)(?:shader[_-]?cache|pipeline[_-]?cache)(?:/|$)'
        Reason = 'shader or pipeline cache'
    }
    [pscustomobject]@{
        Id = 'vita3k-user-data'
        Pattern = '^(?:ux0|ur0|vs0|sa0|tm0|vd0)(?:/|$)|' +
            '^(?:vita3k[-_](?:user|data))(?:/|$)|' +
            '(?:^|/)vita3k/(?:user|data|cache|log|ux0|ur0|vs0|sa0|' +
            'tm0|vd0)(?:/|$)'
        Reason = 'Vita3K user data or emulated Vita partition'
    }
    [pscustomobject]@{
        Id = 'save-data'
        Pattern = '^(?:save|saves|savedata|save-data)(?:/|$)|\.sav$'
        Reason = 'user save data'
    }
    [pscustomobject]@{
        Id = 'build-output'
        Pattern = '^(?:build|out|dist|_build|cmake-build-[^/]+)(?:/|$)|' +
            '(?:^|/)(?:CMakeFiles|\.vs)(?:/|$)|' +
            '(?:^|/)(?:CMakeCache\.txt|build\.ninja|rules\.ninja|' +
            '\.ninja_deps|\.ninja_log)$'
        Reason = 'generated build or IDE output'
    }
)

if ($Tracked -and $PSBoundParameters.ContainsKey('Paths')) {
    throw '-Tracked and -Paths are mutually exclusive.'
}

$pathsToCheck = @(
    if ($PSBoundParameters.ContainsKey('Paths')) {
        $Paths
    } elseif ($Tracked) {
        Get-TrackedPaths -Root $repository
    } else {
        Get-StagedPaths -Root $repository
    }
)

$violations = New-Object System.Collections.Generic.List[object]
foreach ($candidatePath in $pathsToCheck) {
    if ([string]::IsNullOrWhiteSpace($candidatePath)) {
        continue
    }

    $path = ConvertTo-RepositoryPath -Path $candidatePath
    if ($path -match '^(?:/|[A-Za-z]:/|\.\.(?:/|$))') {
        $violations.Add([pscustomobject]@{
            Path = $candidatePath
            Rule = 'outside-repository'
            Reason = 'path is not repository-relative'
        })
        continue
    }

    foreach ($rule in $rules) {
        if ([Regex]::IsMatch(
                $path,
                $rule.Pattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                    [Text.RegularExpressions.RegexOptions]::CultureInvariant
            )) {
            $violations.Add([pscustomobject]@{
                Path = $path
                Rule = $rule.Id
                Reason = $rule.Reason
            })
        }
    }

    $candidateFullPath = [IO.Path]::GetFullPath(
        (Join-Path $repository $path.Replace('/', '\'))
    )
    foreach ($configuredRoot in $configuredRoots) {
        if (Test-PathWithinRoot `
                -Candidate $candidateFullPath `
                -Root $configuredRoot) {
            $violations.Add([pscustomobject]@{
                Path = $path
                Rule = 'configured-private-root'
                Reason = "path is inside configured private root '$configuredRoot'"
            })
        }
    }
}

$orderedViolations = @(
    $violations |
        Sort-Object -Property Path, Rule -Unique
)

if ($ReportOnly) {
    Write-Output $orderedViolations
    return
}

if ($orderedViolations.Count -gt 0) {
    [Console]::Error.WriteLine(
        "Private-content guard rejected $($orderedViolations.Count) staged path(s):"
    )
    foreach ($violation in $orderedViolations) {
        [Console]::Error.WriteLine(
            "  $($violation.Path) [$($violation.Rule)]: $($violation.Reason)"
        )
    }
    throw 'Remove the rejected paths from the Git index and keep them outside the repository.'
}

Write-Host "Private-content guard passed ($($pathsToCheck.Count) path(s) checked)."
