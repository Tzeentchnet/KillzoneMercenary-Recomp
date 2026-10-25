# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pinFile = Join-Path $root 'config\framework.commit'
$submodule = Join-Path $root 'third_party\vitarecomp'
if (-not (Test-Path -LiteralPath $pinFile -PathType Leaf)) {
    throw "Framework pin file is missing: '$pinFile'."
}
$expected = (Get-Content -LiteralPath $pinFile -Raw).Trim()
if ($expected -cnotmatch '^[0-9a-f]{40}$') {
    throw "Framework pin is not a full lowercase commit: '$expected'."
}

$indexLine = (
    & git -C $root ls-files --stage -- third_party/vitarecomp
) | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or
    $indexLine -cnotmatch '^160000 ([0-9a-f]{40}) 0') {
    throw 'third_party/vitarecomp is not an exact Git submodule entry.'
}
$indexCommit = $Matches[1]
if ($indexCommit -cne $expected) {
    throw "Gitlink '$indexCommit' does not match framework pin '$expected'."
}

if (-not (Test-Path -LiteralPath (
        Join-Path $submodule 'CMakeLists.txt'
    ) -PathType Leaf)) {
    throw 'Framework submodule is not initialized recursively.'
}
$checkedOut = (& git -C $submodule rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $checkedOut -cne $expected) {
    throw "Checked-out framework '$checkedOut' does not match '$expected'."
}
$submoduleStatus = @(& git -C $submodule status --porcelain)
if ($LASTEXITCODE -ne 0 -or $submoduleStatus.Count -ne 0) {
    throw 'Framework submodule contains uncommitted or untracked changes.'
}
$remote = (& git -C $submodule remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or
    $remote -cne 'https://github.com/Tzeentchnet/vitarecomp.git') {
    throw "Unexpected framework origin: '$remote'."
}

Write-Host "Framework submodule pin verified: $expected."
