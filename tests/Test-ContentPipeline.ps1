# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inspector = Join-Path `
    $repositoryRoot `
    'tools\content\Inspect-KillzoneDump.ps1'
$wrapper = Join-Path `
    $repositoryRoot `
    'tools\content\Export-KillzoneRuntimeImages.ps1'
$manifestBuilder = Join-Path `
    $repositoryRoot `
    'tools\content\New-KillzoneElfManifest.ps1'
$testParent = Join-Path $repositoryRoot 'private-data\content-tests'
$workRoot = Join-Path $testParent ([Guid]::NewGuid().ToString('N'))
$script:caseCount = 0

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string] $Message
    )

    if ($Expected -cne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-ThrowsLike {
    param(
        [scriptblock] $Action,
        [string] $Pattern
    )

    $caught = $null
    try {
        & $Action | Out-Null
    } catch {
        $caught = $_
    }
    if ($null -eq $caught) {
        throw "Expected an exception matching '$Pattern'."
    }
    if ($caught.Exception.Message -notmatch $Pattern) {
        throw (
            "Exception did not match '$Pattern': " +
            $caught.Exception.Message
        )
    }
}

function Invoke-TestCase {
    param(
        [string] $Name,
        [scriptblock] $Action
    )

    try {
        & $Action
        ++$script:caseCount
    } catch {
        throw (
            "Content pipeline test '$Name' failed: $($_.Exception.Message)`n" +
            $_.ScriptStackTrace
        )
    }
}

function Add-ZipBytes {
    param(
        [System.IO.Compression.ZipArchive] $Archive,
        [string] $EntryPath,
        [byte[]] $Bytes
    )

    $entry = $Archive.CreateEntry(
        $EntryPath,
        [IO.Compression.CompressionLevel]::NoCompression
    )
    $stream = $entry.Open()
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
    } finally {
        $stream.Dispose()
    }
}

function New-SyntheticArchive {
    param(
        [string] $Path,
        [ValidateSet('Protected', 'Visible')]
        [string] $PayloadState = 'Protected',
        [string[]] $Omit = @()
    )

    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Create,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    $archive = New-Object IO.Compression.ZipArchive(
        $stream,
        [IO.Compression.ZipArchiveMode]::Create,
        $false
    )
    try {
        $entries = [ordered]@{
            'app/PCSA00107/eboot.bin' =
                [byte[]] @(0x31, 0x41, 0x59, 0x26, 0x01)
            'app/PCSA00107/game_data/data_ngp.psarc' =
                [byte[]] @(0x27, 0x18, 0x28, 0x18, 0x02)
            'app/PCSA00107/sce_module/libsynthetic.suprx' =
                [byte[]] @(0x10, 0x20, 0x30, 0x40, 0x03)
            'app/PCSA00107/sce_sys/package/work.bin' =
                [byte[]] @(0x01, 0x02, 0x03, 0x04)
            'app/PCSA00107/sce_sys/param.sfo' =
                [byte[]] @(0x00, 0x50, 0x53, 0x46, 0x01)
            'app/PCSA00107/game_data/資料/™.bin' =
                [byte[]] @(0x55, 0x66)
        }
        if ($PayloadState -eq 'Visible') {
            $entries['app/PCSA00107/eboot.bin'] =
                [byte[]] @(0x53, 0x43, 0x45, 0x00, 0x01)
            $entries['app/PCSA00107/game_data/data_ngp.psarc'] =
                [Text.Encoding]::ASCII.GetBytes('PSARsynthetic')
            $entries['app/PCSA00107/sce_module/libsynthetic.suprx'] =
                [byte[]] @(0x7f, 0x45, 0x4c, 0x46, 0x01)
        }

        foreach ($entryPath in $entries.Keys) {
            if ($Omit -contains $entryPath) {
                continue
            }
            Add-ZipBytes `
                -Archive $archive `
                -EntryPath $entryPath `
                -Bytes $entries[$entryPath]
        }
    } finally {
        $archive.Dispose()
        $stream.Dispose()
    }
}

function New-SyntheticElf {
    param(
        [string] $Path,
        [UInt32] $VirtualAddress,
        [UInt32] $MemorySize = 0x1000
    )

    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $ident = New-Object byte[] 16
        $ident[0] = 0x7f
        $ident[1] = 0x45
        $ident[2] = 0x4c
        $ident[3] = 0x46
        $ident[4] = 1
        $ident[5] = 1
        $ident[6] = 1
        $writer.Write($ident)
        $writer.Write([UInt16] 2)
        $writer.Write([UInt16] 40)
        $writer.Write([UInt32] 1)
        $writer.Write([UInt32] 0)
        $writer.Write([UInt32] 52)
        $writer.Write([UInt32] 0)
        $writer.Write([UInt32] 0x05000000)
        $writer.Write([UInt16] 52)
        $writer.Write([UInt16] 32)
        $writer.Write([UInt16] 1)
        $writer.Write([UInt16] 0)
        $writer.Write([UInt16] 0)
        $writer.Write([UInt16] 0)

        $writer.Write([UInt32] 1)
        $writer.Write([UInt32] 0x100)
        $writer.Write($VirtualAddress)
        $writer.Write($VirtualAddress)
        $writer.Write([UInt32] 0x80)
        $writer.Write($MemorySize)
        $writer.Write([UInt32] 5)
        $writer.Write([UInt32] 0x100)

        while ($stream.Position -lt 0x100) {
            $writer.Write([byte] 0)
        }
        $moduleInfo = New-Object byte[] 0x80
        $moduleInfo[2] = 0x01
        $moduleInfo[3] = 0x01
        $moduleName = [Text.Encoding]::ASCII.GetBytes('synthetic')
        [Array]::Copy($moduleName, 0, $moduleInfo, 4, $moduleName.Length)
        $writer.Write($moduleInfo)
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

try {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    [IO.Directory]::CreateDirectory($workRoot) | Out-Null

    $unicodeArchive = Join-Path `
        $workRoot `
        'Synthetic™ [PCSA00107] [NoNpDRM].zip'
    New-SyntheticArchive -Path $unicodeArchive -PayloadState Protected

    Invoke-TestCase 'valid protected ZIP and Unicode path' {
        $json = & $inspector `
            -ArchivePath $unicodeArchive `
            -OutputFormat Json
        $report = $json | ConvertFrom-Json
        Assert-True $report.valid 'Expected valid archive report.'
        Assert-Equal `
            'retail-pfs-nonpdrm' `
            $report.protection.classification `
            'Unexpected retail protection classification.'
        Assert-Equal `
            'protected' `
            $report.protection.pfsState `
            'Unexpected PFS state.'
        Assert-Equal `
            ([IO.Path]::GetFullPath($unicodeArchive)) `
            $report.archive.path `
            'Unicode archive path was not preserved.'
        Assert-Equal 1 $report.modules.Count 'Expected one synthetic module.'
    }

    Invoke-TestCase 'invalid ZIP' {
        $invalidZip = Join-Path $workRoot 'invalid.zip'
        [IO.File]::WriteAllBytes(
            $invalidZip,
            [Text.Encoding]::ASCII.GetBytes('not a zip')
        )
        Assert-ThrowsLike {
            & $inspector -ArchivePath $invalidZip -OutputFormat Json
        } 'Unable to read ZIP central directory'
    }

    Invoke-TestCase 'missing required ZIP entry' {
        $missingZip = Join-Path $workRoot 'missing-work.zip'
        New-SyntheticArchive `
            -Path $missingZip `
            -Omit 'app/PCSA00107/sce_sys/package/work.bin'
        Assert-ThrowsLike {
            & $inspector -ArchivePath $missingZip -OutputFormat Json
        } 'validation error'
    }

    Invoke-TestCase 'visible payload classification' {
        $visibleZip = Join-Path $workRoot 'visible.zip'
        New-SyntheticArchive -Path $visibleZip -PayloadState Visible
        $json = & $inspector `
            -ArchivePath $visibleZip `
            -OutputFormat Json
        $report = $json | ConvertFrom-Json
        Assert-Equal `
            'retail-nonpdrm-payloads-visible' `
            $report.protection.classification `
            'Visible payloads were misclassified.'
        Assert-Equal `
            'payload-signatures-visible' `
            $report.protection.pfsState `
            'Visible payload PFS state was incorrect.'
    }

    $fakeVita3K = Join-Path $workRoot 'fake-vita3k.cmd'
    $portableRoot = Join-Path $workRoot 'portable'
    [IO.Directory]::CreateDirectory($portableRoot) | Out-Null
    $fakeBody = @(
        '@echo off'
        'if "%~1"=="--help" ('
        '  echo synthetic --dump-elfs --installed-path'
        '  exit /b 0'
        ')'
        'echo invoked>>"%~dp0unexpected-execution.txt"'
        'exit /b 0'
    ) -join "`r`n"
    [IO.File]::WriteAllText(
        $fakeVita3K,
        $fakeBody + "`r`n",
        [Text.Encoding]::ASCII
    )

    Invoke-TestCase 'Vita3K dry run' {
        $json = & $wrapper `
            -ArchivePath $unicodeArchive `
            -Vita3KExecutable $fakeVita3K `
            -Vita3KSourceRevision ('a' * 40) `
            -PrivateDataRoot $workRoot `
            -Phase All `
            -DryRun `
            -Redact
        $report = $json | ConvertFrom-Json
        Assert-True $report.dryRun 'Wrapper did not report dry-run mode.'
        Assert-Equal 2 $report.commands.Count 'Expected install and dump plans.'
        Assert-Equal `
            '<private-data-root>' `
            $report.privateDataRoot `
            'Dry-run redaction failed.'
        Assert-True `
            (-not (Test-Path -LiteralPath (
                Join-Path $workRoot 'unexpected-execution.txt'
            ))) `
            'Dry run executed a Vita3K install or dump command.'
    }

    Invoke-TestCase 'missing Vita3K dump capability' {
        $noCapability = Join-Path $workRoot 'no-capability.cmd'
        $body = @(
            '@echo off'
            'if "%~1"=="--help" ('
            '  echo synthetic help without required capability'
            '  exit /b 0'
            ')'
            'exit /b 0'
        ) -join "`r`n"
        [IO.File]::WriteAllText(
            $noCapability,
            $body + "`r`n",
            [Text.Encoding]::ASCII
        )
        Assert-ThrowsLike {
            & $wrapper `
                -ArchivePath $unicodeArchive `
                -Vita3KExecutable $noCapability `
                -Vita3KSourceRevision ('b' * 40) `
                -PrivateDataRoot $workRoot `
                -DryRun
        } 'dump capability is unavailable'
    }

    $archiveHash = (
        Get-FileHash -LiteralPath $unicodeArchive -Algorithm SHA256
    ).Hash

    Invoke-TestCase 'invalid ELF' {
        $invalidRoot = Join-Path $workRoot 'dumps-invalid'
        [IO.Directory]::CreateDirectory($invalidRoot) | Out-Null
        [IO.File]::WriteAllBytes(
            (Join-Path $invalidRoot 'invalid.elf'),
            (New-Object byte[] 64)
        )
        Assert-ThrowsLike {
            & $manifestBuilder `
                -PrivateDataRoot $workRoot `
                -DumpRoot $invalidRoot `
                -ManifestPath (
                    Join-Path $workRoot 'manifests\invalid.json'
                ) `
                -SourceArchivePath $unicodeArchive `
                -SourceArchiveSha256 $archiveHash `
                -Vita3KSourceRevision ('c' * 40)
        } 'invalid ELF magic'
    }

    Invoke-TestCase 'overlapping runtime ranges' {
        $overlapRoot = Join-Path $workRoot 'dumps-overlap'
        New-SyntheticElf `
            -Path (Join-Path $overlapRoot 'a.elf') `
            -VirtualAddress 2197815296 `
            -MemorySize 0x2000
        New-SyntheticElf `
            -Path (Join-Path $overlapRoot 'b.elf') `
            -VirtualAddress 2197819392 `
            -MemorySize 0x1000
        Assert-ThrowsLike {
            & $manifestBuilder `
                -PrivateDataRoot $workRoot `
                -DumpRoot $overlapRoot `
                -ManifestPath (
                    Join-Path $workRoot 'manifests\overlap.json'
                ) `
                -SourceArchivePath $unicodeArchive `
                -SourceArchiveSha256 $archiveHash `
                -Vita3KSourceRevision ('d' * 40)
        } 'Runtime ranges overlap'
    }

    Invoke-TestCase 'deterministic manifest' {
        $dumpRoot = Join-Path $workRoot 'dumps-valid'
        New-SyntheticElf `
            -Path (Join-Path $dumpRoot 'zeta.elf') `
            -VirtualAddress 2181038080
        New-SyntheticElf `
            -Path (Join-Path $dumpRoot 'nested\alpha.elf') `
            -VirtualAddress 2164260864
        $manifestOne = Join-Path $workRoot 'manifests\one.json'
        $manifestTwo = Join-Path $workRoot 'manifests\two.json'

        & $manifestBuilder `
            -PrivateDataRoot $workRoot `
            -DumpRoot $dumpRoot `
            -ManifestPath $manifestOne `
            -SourceArchivePath $unicodeArchive `
            -SourceArchiveSha256 $archiveHash `
            -Vita3KSourceRevision ('e' * 40) |
            Out-Null
        & $manifestBuilder `
            -PrivateDataRoot $workRoot `
            -DumpRoot $dumpRoot `
            -ManifestPath $manifestTwo `
            -SourceArchivePath $unicodeArchive `
            -SourceArchiveSha256 $archiveHash `
            -Vita3KSourceRevision ('e' * 40) |
            Out-Null

        $bytesOne = [IO.File]::ReadAllBytes($manifestOne)
        $bytesTwo = [IO.File]::ReadAllBytes($manifestTwo)
        Assert-True `
            ([Linq.Enumerable]::SequenceEqual($bytesOne, $bytesTwo)) `
            'Repeated manifest output was not byte-identical.'

        $manifest = (
            [IO.File]::ReadAllText($manifestOne) |
                ConvertFrom-Json
        )
        Assert-Equal `
            'nested/alpha.elf' `
            $manifest.modules[0].path `
            'Manifest module ordering was not ordinal.'
        Assert-Equal `
            'zeta.elf' `
            $manifest.modules[1].path `
            'Manifest module ordering was not ordinal.'
    }

    Write-Host (
        "Content pipeline synthetic tests passed: $script:caseCount cases."
    )
} finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    if (
        (Test-Path -LiteralPath $testParent -PathType Container) -and
        @(Get-ChildItem -LiteralPath $testParent -Force).Count -eq 0
    ) {
        Remove-Item -LiteralPath $testParent -Force
    }
    $privateDataDirectory = Split-Path -Parent $testParent
    if (
        (Test-Path -LiteralPath $privateDataDirectory -PathType Container) -and
        @(Get-ChildItem -LiteralPath $privateDataDirectory -Force).Count -eq 0
    ) {
        Remove-Item -LiteralPath $privateDataDirectory -Force
    }
}
