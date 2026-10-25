# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'windows-x64-debug',
        'windows-x64-relwithdebinfo',
        'windows-x64-release'
    )]
    [string] $Preset,
    [switch] $Bootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$frameworkCi = Join-Path $root 'third_party\vitarecomp\tools\ci'
$configuration = switch ($Preset) {
    'windows-x64-debug' { 'Debug' }
    'windows-x64-relwithdebinfo' { 'RelWithDebInfo' }
    'windows-x64-release' { 'Release' }
}
$buildDirectory = Join-Path $root "out\build\$Preset"

function Invoke-Checked {
    param(
        [string] $Label,
        [scriptblock] $Action
    )
    Write-Host "::group::$Label"
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed with exit code $LASTEXITCODE."
        }
    } finally {
        Write-Host '::endgroup::'
    }
}

& (Join-Path $PSScriptRoot 'Test-SubmodulePin.ps1')
if ($Bootstrap) {
    & (Join-Path $frameworkCi 'Install-PinnedTools.ps1') `
        -ToolsRoot (Join-Path $root 'out\ci-tools') `
        -Build |
        Out-Null
}
foreach ($name in @(
    'VITARECOMP_DXC_ROOT',
    'VITARECOMP_VULKAN_HEADERS_ROOT'
)) {
    if ([string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable($name)
        )) {
        throw "$name is unset; use -Bootstrap or provide the pinned dependency."
    }
}

Push-Location $root
try {
    Invoke-Checked -Label "Configure $Preset" -Action {
        & cmake --preset $Preset --fresh
    }
    Invoke-Checked -Label "Build $Preset" -Action {
        & cmake --build --preset $Preset --parallel
    }
    Invoke-Checked -Label 'Verify required build coverage' -Action {
        & (Join-Path $frameworkCi 'Test-BuildCoverage.ps1') `
            -BuildDirectory $buildDirectory `
            -Configuration $configuration `
            -Profile Game
        $listing = (
            & ctest --test-dir $buildDirectory -C $configuration -N 2>&1
        ) -join "`n"
        if ($LASTEXITCODE -ne 0 -or
            $listing -notmatch '(?m)Test\s+#[0-9]+:\s+content-guard-staged\s*$') {
            throw 'Required staged-content guard coverage is missing.'
        }
    }
    Invoke-Checked -Label "CTest $Preset" -Action {
        & ctest --preset $Preset --no-tests=error
    }
    Invoke-Checked -Label 'Report required DX12 WARP self-test' -Action {
        & ctest `
            --test-dir $buildDirectory `
            -C $configuration `
            -R '^native-host-dx12-warp-self-test$' `
            -V `
            --no-tests=error
    }
    Invoke-Checked -Label 'Report Vulkan smoke availability' -Action {
        & ctest `
            --test-dir $buildDirectory `
            -C $configuration `
            -R '^native-host-vulkan-validation-self-test$' `
            -V `
            --no-tests=error
    }
} finally {
    Pop-Location
}

Write-Host "Game Windows build gate passed: $Preset."
