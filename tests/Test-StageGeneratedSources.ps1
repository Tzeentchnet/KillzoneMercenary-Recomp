# SPDX-License-Identifier: GPL-2.0-or-later
# Synthetic regression coverage adapted from the verified prior AOT workflow.

[CmdletBinding()]
param()

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

function Set-TestContent {
    param(
        [string] $Path,
        [string] $Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stageScript = Join-Path $repositoryRoot 'tools\generated\Stage-GeneratedSources.ps1'
$scratch = Join-Path $repositoryRoot (
    'out\tests\stage-generated-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
)
$source = Join-Path $scratch 'source'
$target = Join-Path $scratch 'target'

try {
    New-Item -ItemType Directory -Path $source, $target -Force | Out-Null

    $unmanaged = Join-Path $target 'keep-me.txt'
    Set-TestContent -Path $unmanaged -Value 'unmanaged'
    $unmanagedTime = (Get-Item -LiteralPath $unmanaged).LastWriteTimeUtc.Ticks

    Set-TestContent -Path (Join-Path $source 'only-one.c') -Value 'invalid'
    $failed = $false
    try {
        & $stageScript `
            -SourceDir $source `
            -TargetDir $target `
            -RequiredFile 'generated_registry.c' | Out-Host
    } catch {
        $failed = $true
    }
    Assert-True $failed 'A source missing a required file must fail.'
    Assert-True (
        (Get-Item -LiteralPath $unmanaged).LastWriteTimeUtc.Ticks -eq $unmanagedTime
    ) 'Failed source validation modified the target.'

    Remove-Item -LiteralPath (Join-Path $source 'only-one.c')
    Set-TestContent -Path (Join-Path $source 'generated_registry.c') -Value 'registry-v1'
    Set-TestContent -Path (Join-Path $source 'chunks\generated_000.c') -Value 'chunk-0'
    Set-TestContent -Path (Join-Path $source 'chunks\generated_001.c') -Value 'chunk-1'

    & $stageScript `
        -SourceDir $source `
        -TargetDir $target `
        -RequiredFile 'generated_registry.c' | Out-Host

    $registryTarget = Join-Path $target 'generated_registry.c'
    $chunk0Target = Join-Path $target 'chunks\generated_000.c'
    $chunk1Target = Join-Path $target 'chunks\generated_001.c'
    $manifestTarget = Join-Path $target '.generated-source-manifest.json'
    foreach ($expected in @($registryTarget, $chunk0Target, $chunk1Target, $manifestTarget, $unmanaged)) {
        Assert-True (Test-Path -LiteralPath $expected -PathType Leaf) "Missing '$expected'."
    }

    $timesBeforeNoOp = @{
        registry = (Get-Item -LiteralPath $registryTarget).LastWriteTimeUtc.Ticks
        chunk0 = (Get-Item -LiteralPath $chunk0Target).LastWriteTimeUtc.Ticks
        chunk1 = (Get-Item -LiteralPath $chunk1Target).LastWriteTimeUtc.Ticks
        manifest = (Get-Item -LiteralPath $manifestTarget).LastWriteTimeUtc.Ticks
    }
    Start-Sleep -Milliseconds 1100
    & $stageScript `
        -SourceDir $source `
        -TargetDir $target `
        -RequiredFile 'generated_registry.c' | Out-Host
    Assert-True (
        (Get-Item -LiteralPath $registryTarget).LastWriteTimeUtc.Ticks -eq
            $timesBeforeNoOp.registry
    ) 'No-op staging touched the registry timestamp.'
    Assert-True (
        (Get-Item -LiteralPath $chunk0Target).LastWriteTimeUtc.Ticks -eq
            $timesBeforeNoOp.chunk0
    ) 'No-op staging touched an unchanged chunk timestamp.'
    Assert-True (
        (Get-Item -LiteralPath $manifestTarget).LastWriteTimeUtc.Ticks -eq
            $timesBeforeNoOp.manifest
    ) 'No-op staging rewrote an unchanged manifest.'

    Set-TestContent -Path (Join-Path $source 'chunks\generated_001.c') -Value 'chunk-1-updated'
    Remove-Item -LiteralPath (Join-Path $source 'chunks\generated_000.c')
    Set-TestContent -Path (Join-Path $source 'chunks\generated_002.c') -Value 'chunk-2'
    Start-Sleep -Milliseconds 1100
    & $stageScript `
        -SourceDir $source `
        -TargetDir $target `
        -RequiredFile 'generated_registry.c' | Out-Host

    Assert-True (
        (Get-Item -LiteralPath $registryTarget).LastWriteTimeUtc.Ticks -eq
            $timesBeforeNoOp.registry
    ) 'A delta staging touched an unchanged registry.'
    Assert-True (
        (Get-Item -LiteralPath $chunk1Target).LastWriteTimeUtc.Ticks -ne
            $timesBeforeNoOp.chunk1
    ) 'A changed chunk did not receive a new timestamp.'
    Assert-True (
        (Get-Content -LiteralPath $chunk1Target -Raw) -ceq 'chunk-1-updated'
    ) 'A changed chunk was not updated.'
    Assert-True (
        -not (Test-Path -LiteralPath $chunk0Target)
    ) 'A stale managed chunk was not removed.'
    Assert-True (
        Test-Path -LiteralPath (Join-Path $target 'chunks\generated_002.c') -PathType Leaf
    ) 'A new chunk was not staged.'
    Assert-True (
        Test-Path -LiteralPath $unmanaged -PathType Leaf
    ) 'An unmanaged target file was removed.'

    $manifest = Get-Content -LiteralPath $manifestTarget -Raw | ConvertFrom-Json
    $manifestPaths = @($manifest.files.path)
    Assert-True ($manifest.schemaVersion -eq 1) 'Unexpected staging manifest schema.'
    Assert-True (
        ($manifestPaths -join ',') -ceq (
            'chunks/generated_001.c,chunks/generated_002.c,generated_registry.c'
        )
    ) 'The staging manifest is not deterministic or does not match the source.'

    $failed = $false
    try {
        & $stageScript -SourceDir $source -TargetDir $source | Out-Host
    } catch {
        $failed = $true
    }
    Assert-True $failed 'Overlapping source and target paths must be rejected.'

    Write-Host 'Generated-source staging synthetic tests passed.'
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
