# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [string] $BaseRef,
    [switch] $Bootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$frameworkCi = Join-Path $root 'third_party\vitarecomp\tools\ci'
$requirements = Join-Path $PSScriptRoot 'requirements-quality.txt'

& (Join-Path $PSScriptRoot 'Test-SubmodulePin.ps1')

if ($Bootstrap) {
    & (Join-Path $frameworkCi 'Install-PinnedTools.ps1') `
        -ToolsRoot (Join-Path $root 'out\ci-tools') `
        -Quality `
        -PythonRequirements $requirements |
        Out-Null
}

& (Join-Path $frameworkCi 'Test-StaticQuality.ps1') `
    -RepositoryRoot $root `
    -Profile Game `
    -BaseRef $BaseRef

$python = $env:VITARECOMP_QUALITY_PYTHON
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Pinned JSON Schema Python environment is unavailable; use -Bootstrap.'
}
& $python (Join-Path $PSScriptRoot 'Test-JsonSchemas.py')
if ($LASTEXITCODE -ne 0) {
    throw 'JSON Schema and example validation failed.'
}

& (Join-Path $PSScriptRoot 'Invoke-PowerShellCompatibility.ps1')

$reportDirectory = Join-Path $root 'out\quality-reports'
$reportOne = Join-Path $reportDirectory 'artifact-inventory-a.json'
$reportTwo = Join-Path $reportDirectory 'artifact-inventory-b.json'
& (Join-Path $frameworkCi 'Test-ArtifactSafety.ps1') `
    -RepositoryRoot $root `
    -Profile Game `
    -ReportPath $reportOne
& (Join-Path $frameworkCi 'Test-ArtifactSafety.ps1') `
    -RepositoryRoot $root `
    -Profile Game `
    -ReportPath $reportTwo

$first = [IO.File]::ReadAllBytes($reportOne)
$second = [IO.File]::ReadAllBytes($reportTwo)
if (-not [Linq.Enumerable]::SequenceEqual($first, $second)) {
    throw 'Repeated public artifact inventories were not byte-identical.'
}

Write-Host (
    'Game formatting, static quality, schema, PowerShell compatibility, ' +
    'submodule pin, and artifact safety passed.'
)
