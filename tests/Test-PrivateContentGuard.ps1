# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$guard = Join-Path $repositoryRoot 'tools\content\Guard-PrivateContent.ps1'

$allowedPaths = @(
    'src/game/title_config.cpp'
    'src/host/main.cpp'
    'src/host/save-data.cpp'
    'src/game/shader_cache.cpp'
    'docs/PCSA00107-notes.md'
    'docs/assets/architecture.png'
    'tests/fixtures/archive_reader.zip.txt'
    'patches/vita3k/runtime-dump.patch'
    'LICENSE'
    'LICENSES/GPL-2.0-or-later.txt'
)

$rejectedPaths = @(
    [pscustomobject]@{
        Path = 'incoming/Killzone Mercenary [PCSA00107].zip'
        Rule = 'known-title-content'
    }
    [pscustomobject]@{
        Path = 'app/PCSA00107/eboot.bin'
        Rule = 'known-title-content'
    }
    [pscustomobject]@{
        Path = 'dump/module.elf'
        Rule = 'retail-data'
    }
    [pscustomobject]@{
        Path = 'modules/libRetail.SUPRX'
        Rule = 'retail-data'
    }
    [pscustomobject]@{
        Path = 'game_data/data_ngp.psarc'
        Rule = 'retail-data'
    }
    [pscustomobject]@{
        Path = 'sce_sys/package/work.bin'
        Rule = 'retail-data'
    }
    [pscustomobject]@{
        Path = 'secrets/license.rif'
        Rule = 'key-or-license'
    }
    [pscustomobject]@{
        Path = 'extracted-assets/texture.png'
        Rule = 'extracted-assets'
    }
    [pscustomobject]@{
        Path = 'generated/PCSA00107/module_0.c'
        Rule = 'generated-title-code'
    }
    [pscustomobject]@{
        Path = 'traces/boot.trace'
        Rule = 'trace-or-capture'
    }
    [pscustomobject]@{
        Path = 'captures/frame.rdc'
        Rule = 'trace-or-capture'
    }
    [pscustomobject]@{
        Path = 'shader-cache/pipeline.bin'
        Rule = 'shader-cache'
    }
    [pscustomobject]@{
        Path = 'vita3k-data/ux0/app/content.bin'
        Rule = 'vita3k-user-data'
    }
    [pscustomobject]@{
        Path = 'ux0/user/00/savedata/slot.dat'
        Rule = 'vita3k-user-data'
    }
    [pscustomobject]@{
        Path = 'saves/slot.dat'
        Rule = 'save-data'
    }
    [pscustomobject]@{
        Path = 'build/generated.obj'
        Rule = 'build-output'
    }
    [pscustomobject]@{
        Path = 'local-private/content.dat'
        Rule = 'configured-private-root'
    }
)

$allowedViolations = @(
    & $guard `
        -RepositoryRoot $repositoryRoot `
        -Paths $allowedPaths `
        -PrivateRoot 'local-private' `
        -ReportOnly
)
if ($allowedViolations.Count -ne 0) {
    $summary = ($allowedViolations | ForEach-Object {
        "$($_.Path) [$($_.Rule)]"
    }) -join ', '
    throw "Allowed synthetic paths were rejected: $summary"
}

$rejectedResults = @(
    & $guard `
        -RepositoryRoot $repositoryRoot `
        -Paths ($rejectedPaths.Path) `
        -PrivateRoot 'local-private' `
        -ReportOnly
)

foreach ($expected in $rejectedPaths) {
    $match = @(
        $rejectedResults |
            Where-Object {
                $_.Path -ceq $expected.Path -and $_.Rule -ceq $expected.Rule
            }
    )
    if ($match.Count -eq 0) {
        throw "Expected '$($expected.Path)' to match rule '$($expected.Rule)'."
    }
}

$rejectedPathSet = @($rejectedResults.Path | Sort-Object -Unique)
if ($rejectedPathSet.Count -ne $rejectedPaths.Count) {
    throw 'The rejected synthetic path set did not match the expected set.'
}

Write-Host (
    "Private-content guard synthetic tests passed: " +
    "$($allowedPaths.Count) allowed, $($rejectedPaths.Count) rejected."
)
