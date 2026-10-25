# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testScripts = @(
    'tests\Test-PrivateContentGuard.ps1',
    'tests\Test-ContentPipeline.ps1',
    'tests\Test-StageGeneratedSources.ps1'
)
$hosts = New-Object 'System.Collections.Generic.List[object]'
foreach ($name in @('powershell', 'pwsh')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $knownSources = @(
        $hosts | ForEach-Object { $_.Source }
    )
    if ($null -ne $command -and
        -not $knownSources.Contains($command.Source)) {
        $hosts.Add($command)
    }
}
if ($hosts.Count -eq 0) {
    throw 'No supported PowerShell host is available.'
}

foreach ($hostCommand in $hosts) {
    $version = (
        & $hostCommand.Source -NoLogo -NoProfile -Command (
            '$PSVersionTable.PSVersion.ToString()'
        )
    ).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query '$($hostCommand.Source)'."
    }
    Write-Host "Testing public scripts with $($hostCommand.Name) $version."
    foreach ($relative in $testScripts) {
        & $hostCommand.Source `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File (Join-Path $root $relative)
        if ($LASTEXITCODE -ne 0) {
            throw "$relative failed under $($hostCommand.Name) $version."
        }
    }
    & $hostCommand.Source `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $root 'tools\content\Guard-PrivateContent.ps1') `
        -RepositoryRoot $root `
        -Tracked
    if ($LASTEXITCODE -ne 0) {
        throw "Complete tracked-content guard failed under $version."
    }
}

Write-Host "PowerShell compatibility passed under $($hosts.Count) host(s)."
