# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $HostExecutable,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Content',
        'UnavailableAdapter',
        'InvalidVulkan',
        'RepeatDx12Warp',
        'OptionalDx12Hardware',
        'OptionalVulkanValidation'
    )]
    [string] $Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function ConvertTo-ProcessArgument {
    param([string] $Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-HostProcess {
    param(
        [string[]] $Arguments,
        [hashtable] $Environment = @{}
    )

    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [IO.Path]::GetFullPath($HostExecutable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Arguments = (
        @($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' '
    )
    foreach ($entry in $Environment.GetEnumerator()) {
        $start.EnvironmentVariables[$entry.Key] = [string] $entry.Value
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) {
        throw 'Failed to start the native host.'
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(180000)) {
        $process.Kill()
        throw 'Native host timed out.'
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $stdout + $stderr
    }
}

function Set-UInt16LittleEndian {
    param(
        [byte[]] $Bytes,
        [int] $Offset,
        [UInt16] $Value
    )
    $Bytes[$Offset] = [byte] ($Value -band 0xff)
    $Bytes[$Offset + 1] = [byte] (($Value -shr 8) -band 0xff)
}

function Set-UInt32LittleEndian {
    param(
        [byte[]] $Bytes,
        [int] $Offset,
        [UInt32] $Value
    )
    for ($index = 0; $index -lt 4; ++$index) {
        $Bytes[$Offset + $index] = [byte] (
            ($Value -shr ($index * 8)) -band 0xff
        )
    }
}

function New-SyntheticElf {
    param(
        [string] $Path,
        [UInt32] $BaseAddress,
        [string] $ModuleName,
        [switch] $Protected
    )

    $bytes = New-Object byte[] 512
    if ($Protected) {
        $marker = [Text.Encoding]::ASCII.GetBytes('synthetic-protected-input')
        [Array]::Copy($marker, 0, $bytes, 0, $marker.Length)
    } else {
        $bytes[0] = 0x7f
        $bytes[1] = 0x45
        $bytes[2] = 0x4c
        $bytes[3] = 0x46
        $bytes[4] = 1
        $bytes[5] = 1
        $bytes[6] = 1
        Set-UInt16LittleEndian $bytes 16 2
        Set-UInt16LittleEndian $bytes 18 40
        Set-UInt32LittleEndian $bytes 20 1
        Set-UInt32LittleEndian $bytes 24 0x100
        Set-UInt32LittleEndian $bytes 28 52
        Set-UInt16LittleEndian $bytes 40 52
        Set-UInt16LittleEndian $bytes 42 32
        Set-UInt16LittleEndian $bytes 44 1

        Set-UInt32LittleEndian $bytes 52 1
        Set-UInt32LittleEndian $bytes 56 0
        Set-UInt32LittleEndian $bytes 60 $BaseAddress
        Set-UInt32LittleEndian $bytes 68 512
        Set-UInt32LittleEndian $bytes 72 4096
        Set-UInt32LittleEndian $bytes 76 5
        Set-UInt32LittleEndian $bytes 80 4096

        Set-UInt16LittleEndian $bytes 0x102 0x100
        $name = [Text.Encoding]::ASCII.GetBytes($ModuleName)
        [Array]::Copy($name, 0, $bytes, 0x104, $name.Length)
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-ModuleRecord {
    param(
        [string] $Root,
        [string] $RelativePath,
        [UInt32] $BaseAddress,
        [string] $ModuleName,
        [switch] $Protected
    )

    $path = Join-Path $Root $RelativePath
    New-SyntheticElf `
        -Path $path `
        -BaseAddress $BaseAddress `
        -ModuleName $ModuleName `
        -Protected:$Protected
    return [ordered]@{
        path = $RelativePath.Replace('\', '/')
        sha256 = (
            Get-FileHash -LiteralPath $path -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        fileSize = 512
        moduleInfo = [ordered]@{
            name = $ModuleName
            encodedEntry = '0x00000100'
            segmentIndex = 0
            segmentOffset = 256
            virtualAddress = '0x{0:X8}' -f ($BaseAddress + 0x100)
        }
        programHeaderCount = 1
        loadSegments = @(
            [ordered]@{
                index = 0
                fileOffset = 0
                fileSize = 512
                virtualAddress = '0x{0:X8}' -f $BaseAddress
                memorySize = 4096
                rangeEndExclusive = '0x{0:X8}' -f ($BaseAddress + 4096)
                flags = 'r-x'
                alignment = 4096
            }
        )
    }
}

function Write-SyntheticManifest {
    param(
        [string] $Path,
        [string] $TitleId,
        [object[]] $Modules
    )

    $manifest = [ordered]@{
        schemaVersion = 1
        titleId = $TitleId
        sourceArchive = [ordered]@{
            path = 'C:\synthetic\public.zip'
            sha256 = ('0' * 64)
        }
        vita3k = [ordered]@{
            sourceRevision = '0000000'
            dumpCapability = '--dump-elfs'
        }
        imageFormat = [ordered]@{
            elfClass = 'ELF32'
            byteOrder = 'little-endian'
            machine = 'ARM'
        }
        modules = @($Modules)
    }
    $json = ($manifest | ConvertTo-Json -Depth 16) + "`n"
    [IO.File]::WriteAllText(
        $Path,
        $json,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Invoke-ContentTests {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $workRoot = Join-Path $repositoryRoot 'out\test-data\native-host-integration'
    $contentRoot = Join-Path $workRoot 'app0'
    $manifestPath = Join-Path $workRoot 'runtime-manifest.json'
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    [IO.Directory]::CreateDirectory($contentRoot) | Out-Null

    try {
        $alpha = New-ModuleRecord `
            -Root $contentRoot `
            -RelativePath 'alpha.elf' `
            -BaseAddress 0x10000000 `
            -ModuleName 'public_alpha'
        Write-SyntheticManifest `
            -Path $manifestPath `
            -TitleId 'PCSA00107' `
            -Modules @($alpha)
        $valid = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12',
            '--adapter=warp',
            '--log-level=debug'
        )
        Assert-True `
            ($valid.ExitCode -eq 9) `
            "Valid content returned $($valid.ExitCode), expected 9."
        Assert-True `
            ($valid.Output -match '"event":"content_mounted_read_only"') `
            'Valid content was not mounted read-only.'
        Assert-True `
            ($valid.Output -match '"event":"title_not_implemented"') `
            'Title mode did not take the explicit not-implemented path.'
        Assert-True `
            (-not $valid.Output.Contains($contentRoot)) `
            'Content root leaked into structured logs.'
        Assert-True `
            (-not $valid.Output.Contains($manifestPath)) `
            'Manifest path leaked into structured logs.'
        Assert-True `
            (-not $valid.Output.Contains($alpha.sha256)) `
            'Module hash leaked into structured logs.'
        Assert-True `
            (-not $valid.Output.Contains('alpha.elf')) `
            'Private module path leaked into structured logs.'

        [IO.File]::WriteAllBytes(
            (Join-Path $contentRoot 'alpha.elf'),
            [byte[]] (1..64)
        )
        $changed = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12'
        )
        Assert-True `
            ($changed.ExitCode -eq 3) `
            "Changed module returned $($changed.ExitCode), expected 3."

        $alpha = New-ModuleRecord `
            -Root $contentRoot `
            -RelativePath 'alpha.elf' `
            -BaseAddress 0x10000000 `
            -ModuleName 'public_alpha'
        Write-SyntheticManifest `
            -Path $manifestPath `
            -TitleId 'WRONG0000' `
            -Modules @($alpha)
        $wrongTitle = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12'
        )
        Assert-True `
            ($wrongTitle.ExitCode -eq 3) `
            "Wrong title returned $($wrongTitle.ExitCode), expected 3."

        $traversal = [ordered]@{}
        foreach ($entry in $alpha.GetEnumerator()) {
            $traversal[$entry.Key] = $entry.Value
        }
        $traversal.path = '../escape.elf'
        Write-SyntheticManifest `
            -Path $manifestPath `
            -TitleId 'PCSA00107' `
            -Modules @($traversal)
        $escaped = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12'
        )
        Assert-True `
            ($escaped.ExitCode -eq 3) `
            "Traversal returned $($escaped.ExitCode), expected 3."

        $alpha = New-ModuleRecord `
            -Root $contentRoot `
            -RelativePath 'alpha.elf' `
            -BaseAddress 0x10000000 `
            -ModuleName 'public_alpha'
        $beta = New-ModuleRecord `
            -Root $contentRoot `
            -RelativePath 'beta.elf' `
            -BaseAddress 0x10000000 `
            -ModuleName 'public_beta'
        Write-SyntheticManifest `
            -Path $manifestPath `
            -TitleId 'PCSA00107' `
            -Modules @($alpha, $beta)
        $overlap = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12'
        )
        Assert-True `
            ($overlap.ExitCode -eq 3) `
            "Overlapping ranges returned $($overlap.ExitCode), expected 3."

        $protected = New-ModuleRecord `
            -Root $contentRoot `
            -RelativePath 'protected.elf' `
            -BaseAddress 0x20000000 `
            -ModuleName 'public_protected' `
            -Protected
        Write-SyntheticManifest `
            -Path $manifestPath `
            -TitleId 'PCSA00107' `
            -Modules @($protected)
        $notReady = Invoke-HostProcess -Arguments @(
            "--content-root=$contentRoot",
            "--manifest=$manifestPath",
            '--renderer=dx12'
        )
        Assert-True `
            ($notReady.ExitCode -eq 3) `
            "Protected content returned $($notReady.ExitCode), expected 3."
    } finally {
        if (Test-Path -LiteralPath $workRoot) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
    }
}

switch ($Mode) {
    'Content' {
        Invoke-ContentTests
    }
    'UnavailableAdapter' {
        $result = Invoke-HostProcess -Arguments @(
            '--self-test',
            '--renderer=dx12',
            '--adapter=4294967295',
            '--frames=1'
        )
        Assert-True `
            ($result.ExitCode -eq 5) `
            "Unavailable adapter returned $($result.ExitCode), expected 5."
    }
    'InvalidVulkan' {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $invalidIcd = Join-Path $repositoryRoot 'out\nonexistent-vulkan-icd.json'
        $result = Invoke-HostProcess `
            -Arguments @(
                '--self-test',
                '--renderer=vulkan',
                '--adapter=hardware',
                '--frames=1'
            ) `
            -Environment @{
                VK_ICD_FILENAMES = $invalidIcd
                VK_DRIVER_FILES = $invalidIcd
            }
        Assert-True `
            ($result.ExitCode -eq 4) `
            "Unavailable Vulkan backend returned $($result.ExitCode), expected 4."
    }
    'RepeatDx12Warp' {
        for ($iteration = 0; $iteration -lt 3; ++$iteration) {
            $result = Invoke-HostProcess -Arguments @(
                '--self-test',
                '--renderer=dx12',
                '--adapter=warp',
                '--frames=3',
                '--log-level=debug'
            )
            Assert-True `
                ($result.ExitCode -eq 0) `
                "Repeated WARP run returned $($result.ExitCode)."
            Assert-True `
                ($result.Output -match '"event":"window_lifecycle_exercised"') `
                'Repeated WARP run did not exercise resize lifecycle.'
            Assert-True `
                ($result.Output -match '"event":"self_test_passed"') `
                'Repeated WARP run did not pass conformance.'
        }
    }
    'OptionalDx12Hardware' {
        $result = Invoke-HostProcess -Arguments @(
            '--self-test',
            '--renderer=dx12',
            '--adapter=hardware',
            '--frames=4'
        )
        if ($result.ExitCode -in @(4, 5)) {
            Write-Host (
                'SKIP: DX12 hardware smoke unavailable; no usable hardware ' +
                "adapter (host exit $($result.ExitCode))."
            )
            exit 77
        }
        Assert-True `
            ($result.ExitCode -eq 0) `
            "DX12 hardware run returned $($result.ExitCode)."
    }
    'OptionalVulkanValidation' {
        $result = Invoke-HostProcess -Arguments @(
            '--self-test',
            '--renderer=vulkan',
            '--adapter=hardware',
            '--validation',
            '--frames=4'
        )
        if ($result.ExitCode -in @(4, 5)) {
            Write-Host (
                'SKIP: Vulkan smoke unavailable; no usable loader, ICD, or ' +
                "adapter (host exit $($result.ExitCode))."
            )
            exit 77
        }
        Assert-True `
            ($result.ExitCode -eq 0) `
            "Vulkan validation run returned $($result.ExitCode)."
    }
}

Write-Host "Native host integration mode '$Mode' passed."
