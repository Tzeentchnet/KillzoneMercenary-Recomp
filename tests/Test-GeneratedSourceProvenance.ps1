# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [string] $ExportBundleRoot,

    [string] $ExportRuntimeManifest
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

function Set-TestContent {
    param(
        [string] $Path,
        [string] $Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Assert-Fails {
    param(
        [scriptblock] $Action,
        [string] $Message,
        [string[]] $Forbidden = @()
    )

    $failed = $false
    $failureText = ''
    try {
        & $Action
    } catch {
        $failed = $true
        $failureText = $_.Exception.Message
    }
    Assert-True -Condition $failed -Message $Message
    foreach ($secret in $Forbidden) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            Assert-True `
                -Condition (
                    $failureText.IndexOf(
                        $secret,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -lt 0
                ) `
                -Message 'A provenance failure disclosed private evidence.'
        }
    }
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$creator = Join-Path (
    $repositoryRoot
) 'tools\generated\New-GeneratedSourceProvenance.ps1'
$validator = Join-Path (
    $repositoryRoot
) 'tools\generated\Test-GeneratedSourceProvenance.ps1'
$stage = Join-Path (
    $repositoryRoot
) 'tools\generated\Stage-GeneratedSources.ps1'
. (Join-Path (
    $repositoryRoot
) 'tools\generated\GeneratedSourceProvenance.Common.ps1')

$scratch = Join-Path $repositoryRoot (
    'out\tests\generated-provenance-' +
    $PID +
    '-' +
    [Guid]::NewGuid().ToString('N')
)

function New-SyntheticFixture {
    param(
        [string] $Name,
        [uint32] $BodyCuts = 0,
        [uint32] $Unreported = 0,
        [uint32] $Unclassified = 0,
        [bool] $Pc = $true,
        [uint32] $EntryMatches = 1,
        [uint32] $AggregateBodyCutDelta = 0,
        [uint32] $AggregatePartitionDelta = 0,
        [bool] $Tls = $true
    )

    $root = Join-Path $scratch $Name
    $source = Join-Path $root 'source'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    $runtimeManifest = Join-Path $root 'runtime-manifest.json'
    $generator = Join-Path $root 'armrecomp.exe'
    $commandSpec = Join-Path $root 'commands.json'
    Set-TestContent `
        -Path $runtimeManifest `
        -Value '{"synthetic":"runtime-manifest"}'
    Set-TestContent -Path $generator -Value 'synthetic-armrecomp-binary'

    Set-TestContent `
        -Path (Join-Path $source 'modules\module_main.c') `
        -Value '/* synthetic module source */'
    Set-TestContent `
        -Path (Join-Path $source 'modules\module_main_000.c') `
        -Value '/* synthetic module partition */'
    Set-TestContent `
        -Path (Join-Path $source 'modules\module_main.h') `
        -Value '/* synthetic module header */'
    Set-TestContent `
        -Path (Join-Path $source 'generated_registry.c') `
        -Value '/* synthetic registry source */'
    Set-TestContent `
        -Path (Join-Path $source 'generated_registry.h') `
        -Value '/* synthetic registry header */'
    Set-TestContent `
        -Path (Join-Path $source 'modules\module_main.report.txt') `
        -Value 'synthetic module report'
    Set-TestContent `
        -Path (Join-Path $source 'generated_registry.report.txt') `
        -Value 'synthetic aggregate report'

    [uint32] $namedTraps = 2
    [uint32] $trapped = $namedTraps + $Unclassified
    [uint32] $translated = 10 - $trapped
    $moduleStructural = $true
    $productionReady = (
        $trapped -eq 0 -and
        $BodyCuts -eq 0 -and
        $Unreported -eq 0
    )
    $aggregateReady = (
        $moduleStructural -and
        $BodyCuts -eq 0 -and
        $Unreported -eq 0 -and
        $Unclassified -eq 0 -and
        $Pc -and
        $EntryMatches -eq 1
    )

    $moduleReport = [pscustomobject][ordered]@{
        schemaVersion = 4
        generator = 'armrecomp'
        module = [pscustomobject][ordered]@{
            id = 'module_main'
            name = 'synthetic_module'
        }
        strictUnsupported = $true
        structuralReady = $moduleStructural
        productionReady = $productionReady
        instrumentation = [pscustomobject][ordered]@{
            functionEntry = $true
            pc = $Pc
        }
        entry = [pscustomobject][ordered]@{
            present = $true
            rawAddress = '0x00001000'
            dispatchKey = '0x00001001'
            resolved = $true
        }
        tls = [pscustomobject][ordered]@{
            present = $Tls
            resolved = $Tls
            address = if ($Tls) { '0x00001800' } else { '0x00000000' }
            fileSize = if ($Tls) { 4 } else { 0 }
            memorySize = if ($Tls) { 32 } else { 0 }
            alignment = if ($Tls) { 64 } else { 0 }
        }
        functions = [pscustomobject][ordered]@{
            emitted = 1
            discovered = 1
            dropped = 0
            promotedWeakRoots = 0
        }
        instructions = [pscustomobject][ordered]@{
            total = 10
            translated = $translated
            trapped = $trapped
            bodyCuts = $BodyCuts
        }
        traps = [pscustomobject][ordered]@{
            total = $trapped
            classified = $namedTraps
            unclassified = $Unclassified
            other = 0
            kinds = @(
                [pscustomobject][ordered]@{
                    kind = 'synthetic_named_trap'
                    count = $namedTraps
                }
            )
        }
        partitions = [pscustomobject][ordered]@{
            unreported = $Unreported
            items = @(
                [pscustomobject][ordered]@{
                    unit = 'part-000'
                    functions = 1
                    instructions = 10
                    firstKey = '0x00001001'
                    lastKey = '0x00001001'
                }
            )
        }
    }
    Write-ProvenanceCanonicalJson `
        -Path (Join-Path $source 'modules\module_main.report.json') `
        -Value $moduleReport

    $sidecar = [pscustomobject][ordered]@{
        schemaVersion = 4
        abiVersion = 4
        generator = 'armrecomp'
        module = [pscustomobject][ordered]@{
            id = 'module_main'
            name = 'synthetic_module'
            descriptorSymbol = 'vita_generated_module_module_main'
        }
        ranges = [pscustomobject][ordered]@{
            load = @(
                [pscustomobject][ordered]@{
                    begin = '0x00001000'
                    endExclusive = '0x00002000'
                }
            )
            executable = @(
                [pscustomobject][ordered]@{
                    begin = '0x00001000'
                    endExclusive = '0x00002000'
                }
            )
        }
        dispatch = [pscustomobject][ordered]@{
            count = 1
            entries = @()
        }
        entry = [pscustomobject][ordered]@{
            present = $true
            rawAddress = '0x00001000'
            dispatchKey = '0x00001001'
            function = 'vita_func_module_main_00001001'
            resolved = $true
        }
        tls = [pscustomobject][ordered]@{
            present = $Tls
            resolved = $Tls
            address = if ($Tls) { '0x00001800' } else { '0x00000000' }
            fileSize = if ($Tls) { 4 } else { 0 }
            memorySize = if ($Tls) { 32 } else { 0 }
            alignment = if ($Tls) { 64 } else { 0 }
        }
        functionImports = [pscustomobject][ordered]@{
            count = 0
            items = @()
        }
        exports = [pscustomobject][ordered]@{
            count = 0
            functions = 0
            variables = 0
            tlsVariables = 0
            items = @()
        }
        variableImports = [pscustomobject][ordered]@{
            count = 0
            items = @()
        }
        report = [pscustomobject][ordered]@{
            schemaVersion = 4
            structuralReady = $moduleStructural
            productionReady = $productionReady
            strictUnsupported = $true
            pcInstrumentation = $Pc
            unclassifiedTrapCount = $Unclassified
        }
    }
    Write-ProvenanceCanonicalJson `
        -Path (Join-Path $source 'modules\module_main.module.json') `
        -Value $sidecar

    $tlsLayoutItems = @()
    if ($Tls) {
        $tlsLayoutItems = @(
            [pscustomobject][ordered]@{
                moduleId = 'module_main'
                descriptorIndex = 0
                order = 0
                offset = 0
                alignment = 64
            }
        )
    }
    $aggregateReport = [pscustomobject][ordered]@{
        schemaVersion = 4
        generator = 'armrecomp-compose'
        entryModuleId = 'module_main'
        moduleCount = 1
        strictUnsupported = $true
        structuralReady = $aggregateReady
        entryEligible = $aggregateReady
        productionReady = $productionReady
        instrumentation = [pscustomobject][ordered]@{
            functionEntry = $true
            pc = $Pc
        }
        entry = [pscustomobject][ordered]@{
            moduleId = 'module_main'
            rawAddress = '0x00001000'
            dispatchKey = '0x00001001'
            symbol = 'vita_func_module_main_00001001'
            matches = $EntryMatches
        }
        tlsLayout = [pscustomobject][ordered]@{
            moduleCount = if ($Tls) { 1 } else { 0 }
            dataSize = if ($Tls) { 32 } else { 0 }
            dataAlignment = if ($Tls) { 64 } else { 16 }
            items = $tlsLayoutItems
        }
        totals = [pscustomobject][ordered]@{
            ranges = [pscustomobject][ordered]@{
                load = 1
                executable = 1
            }
            dispatchEntries = 1
            functions = $moduleReport.functions
            instructions = [pscustomobject][ordered]@{
                total = 10
                translated = $translated
                trapped = $trapped
                bodyCuts = $BodyCuts + $AggregateBodyCutDelta
            }
            traps = [pscustomobject][ordered]@{
                total = $trapped
                classified = $namedTraps
                unclassified = $Unclassified
                other = 0
                kinds = @(
                    [pscustomobject][ordered]@{
                        kind = 'synthetic_named_trap'
                        count = $namedTraps
                    }
                )
            }
            partitions = [pscustomobject][ordered]@{
                reported = 1 + $AggregatePartitionDelta
                unreported = $Unreported
            }
            metadata = [pscustomobject][ordered]@{
                tlsModules = if ($Tls) { 1 } else { 0 }
                functionImports = 0
                functionExports = 0
                variableExports = 0
                tlsVariableExports = 0
                variableImports = 0
                variableSites = 0
            }
        }
        modules = @(
            [pscustomobject][ordered]@{
                id = 'module_main'
                name = 'synthetic_module'
                descriptorSymbol = 'vita_generated_module_module_main'
                ranges = $sidecar.ranges
                dispatchEntries = 1
                entry = [pscustomobject][ordered]@{
                    present = $true
                    rawAddress = '0x00001000'
                    dispatchKey = '0x00001001'
                    function = 'vita_func_module_main_00001001'
                    resolved = $true
                }
                tls = [pscustomobject][ordered]@{
                    present = $Tls
                    resolved = $Tls
                    address = if ($Tls) {
                        '0x00001800'
                    } else {
                        '0x00000000'
                    }
                    fileSize = if ($Tls) { 4 } else { 0 }
                    memorySize = if ($Tls) { 32 } else { 0 }
                    alignment = if ($Tls) { 64 } else { 0 }
                    order = if ($Tls) { 0 } else { $null }
                    offset = if ($Tls) { 0 } else { $null }
                }
                functionImports = [pscustomobject][ordered]@{
                    count = 0
                    items = @()
                }
                exports = $sidecar.exports
                variableImports = [pscustomobject][ordered]@{
                    count = 0
                    siteCount = 0
                    items = @()
                }
                report = [pscustomobject][ordered]@{
                    structuralReady = $moduleStructural
                    productionReady = $productionReady
                    instrumentation = $moduleReport.instrumentation
                    functions = $moduleReport.functions
                    instructions = $moduleReport.instructions
                    traps = [pscustomobject][ordered]@{
                        total = $trapped
                        classified = $namedTraps
                        unclassified = $Unclassified
                        other = 0
                        kinds = 1
                    }
                    partitions = [pscustomobject][ordered]@{
                        reported = 1
                        unreported = $Unreported
                    }
                }
            }
        )
    }
    Write-ProvenanceCanonicalJson `
        -Path (Join-Path $source 'generated_registry.report.json') `
        -Value $aggregateReport

    $commands = [pscustomobject][ordered]@{
        commands = @(
            [pscustomobject][ordered]@{
                sequence = 0
                phase = 'emit'
                moduleId = 'module_main'
                executable = 'armrecomp'
                arguments = @(
                    'emit',
                    '--module-id',
                    'module_main',
                    'inputs/module_main.elf',
                    'modules/module_main.c'
                )
            },
            [pscustomobject][ordered]@{
                sequence = 1
                phase = 'compose'
                moduleId = $null
                executable = 'armrecomp'
                arguments = @(
                    'compose',
                    '--entry-module',
                    'module_main',
                    '--output',
                    'generated_registry.c',
                    'modules/module_main.module.json',
                    'modules/module_main.report.json'
                )
            }
        )
        environment = @(
            [pscustomobject][ordered]@{
                name = 'VITARECOMP_EMIT_PC'
                value = if ($Pc) { '1' } else { '0' }
            },
            [pscustomobject][ordered]@{
                name = 'VITARECOMP_EMIT_SPLIT'
                value = $null
            },
            [pscustomobject][ordered]@{
                name = 'VITARECOMP_EMIT_SPLIT_INSNS'
                value = $null
            },
            [pscustomobject][ordered]@{
                name = 'VITARECOMP_WHY'
                value = $null
            }
        )
    }
    Write-ProvenanceCanonicalJson -Path $commandSpec -Value $commands

    return [pscustomobject]@{
        Root = $root
        Source = $source
        RuntimeManifest = $runtimeManifest
        Generator = $generator
        CommandSpec = $commandSpec
        Provenance = Join-Path $source '.generated-source-provenance.json'
    }
}

function Set-CompileableSyntheticBundle {
    param([object] $Fixture)

    Set-TestContent `
        -Path (Join-Path $Fixture.Source 'modules\module_main.h') `
        -Value @'
/* Synthetic armrecomp-compatible module header. */
#ifndef KZMRECOMP_SYNTHETIC_MODULE_MAIN_H
#define KZMRECOMP_SYNTHETIC_MODULE_MAIN_H

#include "vitarecomp/generated_module.h"

#ifdef __cplusplus
extern "C" {
#endif

void vita_hle_memcpy(void);
void vita_hle_sceKernelGetProcessId(void);
void vita_func_module_main_00001001(void);
extern vita_fn vita_import_target_module_main_00000194;
extern const vita_generated_module_descriptor
    vita_generated_module_module_main;

#ifdef __cplusplus
}
#endif

#endif
'@
    Set-TestContent `
        -Path (Join-Path $Fixture.Source 'modules\module_main.c') `
        -Value @'
/* Synthetic armrecomp-compatible module descriptor. */
#include "module_main.h"

static const vita_dispatch_entry vita_functions_module_main[] = {
    { 0x00001001u, vita_func_module_main_00001001 },
    { 0x00001100u, vita_hle_memcpy }
};

vita_fn vita_import_target_module_main_00000194 = vita_hle_memcpy;

static const vita_fn_import vita_fn_imports_module_main[] = {
    {
        0x11223344u,
        0xAABBCCDDu,
        0x00001100u,
        0x00000194u,
        "SceSynthetic::memcpy",
        1u,
        &vita_import_target_module_main_00000194
    }
};

const vita_generated_module_descriptor vita_generated_module_module_main = {
    VITA_GENERATED_MODULE_ABI_VERSION,
    (uint32_t)sizeof(vita_generated_module_descriptor),
    "module_main",
    "synthetic_module",
    vita_functions_module_main,
    2u,
    1u,
    0x00001000u,
    0x00001001u,
    vita_func_module_main_00001001,
    1u,
    { 0u, 0u, 0u, 0u, 0u, 0u },
    vita_fn_imports_module_main,
    1u,
    0,
    0u,
    {
        VITA_GENERATED_REPORT_SCHEMA_VERSION,
        1u,
        0u,
        1u,
        VITA_GENERATED_INSTRUMENT_FUNCTION_ENTRY |
            VITA_GENERATED_INSTRUMENT_PC,
        2u,
        0u,
        0u,
        0u
    }
};
'@
    Set-TestContent `
        -Path (Join-Path $Fixture.Source 'modules\module_main_000.c') `
        -Value @'
/* Synthetic armrecomp-compatible module partition. */
#include "module_main.h"
#include "vitarecomp/recomp_rt.h"

#include <stdlib.h>

void vita_func_module_main_00001001(void) {
    const char *strict = getenv("KZMRECOMP_SYNTHETIC_ENTRY_STRICT");
    if (strict != 0 && strict[0] == '1' && strict[1] == '\0') {
        vita_trap_unimpl(
            0x00001000u,
            0xE7F000F0u,
            "synthetic named strict failure");
    }
    r0 = 0u;
    vita_call(vita_hle_sceKernelGetProcessId);
    if (r0 != 0x40010000u) {
        vita_trap_unimpl(
            0x00001000u,
            0xE7F000F1u,
            "synthetic generated/runtime CPU ABI mismatch");
    }
    vita_call(vita_import_target_module_main_00000194);
}
'@
    Set-TestContent `
        -Path (
            Join-Path $Fixture.Source (
                'modules\module_main_imports\vita_hle_memcpy.c'
            )
        ) `
        -Value @'
/* Synthetic generated import default; the framework implementation wins. */
#include "vitarecomp/recomp_rt.h"

void vita_hle_memcpy(void) {
    vita_trap_import(
        0x00001100u,
        0xAABBCCDDu,
        "synthetic import default selected unexpectedly");
}
'@
    Set-TestContent `
        -Path (Join-Path $Fixture.Source 'generated_registry.h') `
        -Value @'
/* Synthetic armrecomp compose registry header. */
#ifndef KZMRECOMP_SYNTHETIC_GENERATED_REGISTRY_H
#define KZMRECOMP_SYNTHETIC_GENERATED_REGISTRY_H

#include "vitarecomp/generated_module.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const vita_generated_module_descriptor *const
    vita_generated_image_modules[];
extern const uint32_t vita_generated_image_module_count;
extern const vita_generated_tls_layout vita_generated_image_tls_layout;
extern const vita_dispatch_entry vita_generated_image_dispatch[];
extern const uint32_t vita_generated_image_dispatch_count;

const vita_generated_module_descriptor *
vita_generated_image_entry_module(void);
vita_fn vita_generated_image_entry(void);
vita_dispatch_status vita_generated_image_init_checked(void);
void vita_generated_image_init(void);

#ifdef __cplusplus
}
#endif

#endif
'@
    Set-TestContent `
        -Path (Join-Path $Fixture.Source 'generated_registry.c') `
        -Value @'
/* Synthetic armrecomp compose registry. */
#include "generated_registry.h"

extern const vita_generated_module_descriptor
    vita_generated_module_module_main;
extern void vita_func_module_main_00001001(void);
extern void vita_hle_memcpy(void);

const vita_generated_module_descriptor *const
vita_generated_image_modules[] = {
    &vita_generated_module_module_main
};
const uint32_t vita_generated_image_module_count = 1u;
const vita_generated_tls_layout vita_generated_image_tls_layout = {
    VITA_GENERATED_MODULE_ABI_VERSION,
    (uint32_t)sizeof(vita_generated_tls_layout),
    0,
    1u,
    0u,
    0u,
    16u
};

const vita_dispatch_entry vita_generated_image_dispatch[] = {
    { 0x00001001u, vita_func_module_main_00001001 },
    { 0x00001100u, vita_hle_memcpy }
};
const uint32_t vita_generated_image_dispatch_count = 2u;

const vita_generated_module_descriptor *
vita_generated_image_entry_module(void) {
    return &vita_generated_module_module_main;
}

vita_fn vita_generated_image_entry(void) {
    return vita_func_module_main_00001001;
}

vita_dispatch_status vita_generated_image_init_checked(void) {
    return vita_dispatch_init_checked(
        vita_generated_image_dispatch,
        vita_generated_image_dispatch_count);
}

void vita_generated_image_init(void) {
    (void)vita_generated_image_init_checked();
}
'@

    $sidecarPath = Join-Path (
        $Fixture.Source
    ) 'modules\module_main.module.json'
    $sidecar = Read-ProvenanceJson `
        -Path $sidecarPath `
        -Code 'synthetic-sidecar'
    $functionImport = [pscustomobject][ordered]@{
        key = '0x00001100'
        stubAddress = '0x00001100'
        targetSite = '0x00000194'
        libraryNid = '0x11223344'
        functionNid = '0xAABBCCDD'
        name = 'SceSynthetic::memcpy'
        symbol = 'vita_hle_memcpy'
        targetSlot = 'vita_import_target_module_main_00000194'
        strictUnsupported = $true
    }
    $sidecar.dispatch.count = 2
    $sidecar.dispatch.entries = @(
        [pscustomobject][ordered]@{
            key = '0x00001001'
            kind = 'function'
            symbol = 'vita_func_module_main_00001001'
        },
        [pscustomobject][ordered]@{
            key = '0x00001100'
            kind = 'functionImport'
            symbol = 'vita_hle_memcpy'
            libraryNid = '0x11223344'
            functionNid = '0xAABBCCDD'
        }
    )
    $sidecar.functionImports.count = 1
    $sidecar.functionImports.items = @($functionImport)
    Write-ProvenanceCanonicalJson -Path $sidecarPath -Value $sidecar

    $aggregatePath = Join-Path (
        $Fixture.Source
    ) 'generated_registry.report.json'
    $aggregate = Read-ProvenanceJson `
        -Path $aggregatePath `
        -Code 'synthetic-aggregate'
    $aggregate.totals.dispatchEntries = 2
    $aggregate.totals.metadata.functionImports = 1
    $aggregate.modules[0].dispatchEntries = 2
    $aggregate.modules[0].functionImports = $sidecar.functionImports
    Write-ProvenanceCanonicalJson -Path $aggregatePath -Value $aggregate
}

function Invoke-Creator {
    param([object] $Fixture)

    & $creator `
        -SourceRoot $Fixture.Source `
        -RuntimeManifest $Fixture.RuntimeManifest `
        -GeneratorExecutable $Fixture.Generator `
        -CommandSpecFile $Fixture.CommandSpec `
        -AggregateReport 'generated_registry.report.json' `
        -EntryModuleId 'module_main' `
        -OutputFile '.generated-source-provenance.json' `
        -RepositoryRoot $repositoryRoot
}

function Invoke-Validator {
    param([object] $Fixture)

    & $validator `
        -ProvenanceFile $Fixture.Provenance `
        -SourceRoot $Fixture.Source `
        -RuntimeManifest $Fixture.RuntimeManifest `
        -RepositoryRoot $repositoryRoot `
        -GeneratorExecutable $Fixture.Generator `
        -Quiet
}

function Copy-ProvenanceDocument {
    param([object] $Fixture)

    return Read-ProvenanceJson `
        -Path $Fixture.Provenance `
        -Code 'test-provenance'
}

if (-not [string]::IsNullOrWhiteSpace($ExportBundleRoot)) {
    $exportRoot = [IO.Path]::GetFullPath($ExportBundleRoot).TrimEnd('\')
    $allowedExportRoot = [IO.Path]::GetFullPath(
        (Join-Path $repositoryRoot 'out\tests')
    ).TrimEnd('\')
    if (-not $exportRoot.StartsWith(
        $allowedExportRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Synthetic generated bundles must use the ignored test root.'
    }
    if (Test-Path -LiteralPath $exportRoot) {
        Remove-Item -LiteralPath $exportRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    $scratch = $exportRoot
    $exportFixture = New-SyntheticFixture -Name 'generator' -Tls $false
    if (-not [string]::IsNullOrWhiteSpace($ExportRuntimeManifest)) {
        $runtimeOverride = [IO.Path]::GetFullPath(
            $ExportRuntimeManifest
        )
        if (-not (Test-Path -LiteralPath $runtimeOverride -PathType Leaf)) {
            throw 'The synthetic export runtime manifest is unavailable.'
        }
        [IO.File]::WriteAllBytes(
            $exportFixture.RuntimeManifest,
            [IO.File]::ReadAllBytes($runtimeOverride)
        )
    }
    Set-CompileableSyntheticBundle -Fixture $exportFixture
    Invoke-Creator -Fixture $exportFixture | Out-Null
    Invoke-Validator -Fixture $exportFixture
    & $stage `
        -SourceDir $exportFixture.Source `
        -TargetDir (Join-Path $exportRoot 'staged') `
        -RequiredProvenance '.generated-source-provenance.json' `
        -RuntimeManifest $exportFixture.RuntimeManifest | Out-Null
    Write-Host 'Synthetic generated bundle staged.'
    return
}

try {
    $valid = New-SyntheticFixture -Name 'valid'
    $successOutput = (Invoke-Creator -Fixture $valid 6>&1 | Out-String)
    Assert-True `
        -Condition (
            $successOutput.IndexOf(
                $valid.Root,
                [StringComparison]::OrdinalIgnoreCase
            ) -lt 0
        ) `
        -Message 'Creator output disclosed a private path.'
    Invoke-Validator -Fixture $valid
    $validDocument = Copy-ProvenanceDocument -Fixture $valid
    Assert-True `
        -Condition (
            [uint64] $validDocument.schemaVersion -eq 2 -and
            [uint64] $validDocument.generator.moduleSidecarSchemaVersion -eq
                4 -and
            $validDocument.aggregate.entryEligible -eq $true -and
            $validDocument.aggregate.productionReady -eq $false -and
            [uint64] $validDocument.aggregate.classifiedNamedTraps -eq 2 -and
            [uint64] $validDocument.aggregate.tlsLayout.moduleCount -eq 1 -and
            [uint64] $validDocument.aggregate.tlsLayout.dataAlignment -eq
                64 -and
            [uint64] $validDocument.modules[0].tls.alignment -eq 64 -and
            @($validDocument.aggregate.blockers).Count -eq 0
        ) `
        -Message (
            'Fully classified named traps did not preserve entry eligibility.'
        )
    $firstBytes = [IO.File]::ReadAllBytes($valid.Provenance)
    $firstTime = (Get-Item -LiteralPath $valid.Provenance).LastWriteTimeUtc.Ticks
    Start-Sleep -Milliseconds 1100
    Invoke-Creator -Fixture $valid | Out-Null
    $secondBytes = [IO.File]::ReadAllBytes($valid.Provenance)
    Assert-True `
        -Condition (
            [Linq.Enumerable]::SequenceEqual($firstBytes, $secondBytes)
        ) `
        -Message 'Repeated provenance creation was not byte-identical.'
    Assert-True `
        -Condition (
            (Get-Item -LiteralPath $valid.Provenance).LastWriteTimeUtc.Ticks -eq
                $firstTime
        ) `
        -Message 'Repeated provenance creation touched an unchanged file.'

    $malformedPath = Join-Path $valid.Source 'malformed-provenance.json'
    Set-TestContent -Path $malformedPath -Value '{'
    Assert-Fails -Message 'Malformed provenance JSON must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.PSObject.Properties.Remove('entryPolicyVersion')
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'A malformed provenance schema must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.schemaVersion = '1'
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'A malformed provenance type must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.aggregate.tlsLayout.items[0].offset = 16
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'A TLS aggregate offset mismatch must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.framework.commit = '1111111111111111111111111111111111111111'
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    $runtimeHash = Get-ProvenanceSha256 -Path $valid.RuntimeManifest
    Assert-Fails `
        -Message 'A framework revision mismatch must fail.' `
        -Forbidden @($valid.Root, $runtimeHash) `
        -Action {
            & $validator `
                -ProvenanceFile $malformedPath `
                -SourceRoot $valid.Source `
                -RuntimeManifest $valid.RuntimeManifest `
                -RepositoryRoot $repositoryRoot `
                -Quiet
        }

    Set-TestContent `
        -Path $valid.RuntimeManifest `
        -Value '{"synthetic":"changed-runtime-manifest"}'
    Assert-Fails -Message 'A runtime-manifest mismatch must fail.' -Action {
        Invoke-Validator -Fixture $valid
    }
    Set-TestContent `
        -Path $valid.RuntimeManifest `
        -Value '{"synthetic":"runtime-manifest"}'

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $temporary = $mutated.generatedFiles[0]
    $mutated.generatedFiles[0] = $mutated.generatedFiles[1]
    $mutated.generatedFiles[1] = $temporary
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'An unordered inventory must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.generatedFiles[1].path = (
        [string] $mutated.generatedFiles[0].path
    ).ToUpperInvariant()
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'A case-colliding inventory must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.modules[0].sidecar.path = '../module.module.json'
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'A traversal path must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    $mutated = Copy-ProvenanceDocument -Fixture $valid
    $mutated.generator.commands[0].arguments[3] = 'C:/synthetic/module.elf'
    Write-ProvenanceCanonicalJson -Path $malformedPath -Value $mutated
    Assert-Fails -Message 'An absolute command path must fail.' -Action {
        & $validator `
            -ProvenanceFile $malformedPath `
            -SourceRoot $valid.Source `
            -RuntimeManifest $valid.RuntimeManifest `
            -RepositoryRoot $repositoryRoot `
            -Quiet
    }

    Set-TestContent `
        -Path (Join-Path $valid.Source 'modules\unexpected.c') `
        -Value '/* unreported generated file */'
    Assert-Fails -Message 'Generated inventory drift must fail.' -Action {
        Invoke-Validator -Fixture $valid
    }
    Remove-Item -LiteralPath (
        Join-Path $valid.Source 'modules\unexpected.c'
    )
    $moduleSource = Join-Path $valid.Source 'modules\module_main.c'
    Set-TestContent -Path $moduleSource -Value '/* changed module source */'
    Assert-Fails -Message 'A generated-file digest mismatch must fail.' -Action {
        Invoke-Validator -Fixture $valid
    }
    Set-TestContent -Path $moduleSource -Value '/* synthetic module source */'

    $badTls = New-SyntheticFixture -Name 'tls-alignment-mismatch'
    $badTlsSidecarPath =
        Join-Path $badTls.Source 'modules\module_main.module.json'
    $badTlsReportPath =
        Join-Path $badTls.Source 'modules\module_main.report.json'
    $badTlsAggregatePath =
        Join-Path $badTls.Source 'generated_registry.report.json'
    $badTlsSidecar = Read-ProvenanceJson `
        -Path $badTlsSidecarPath `
        -Code 'bad-tls-sidecar'
    $badTlsReport = Read-ProvenanceJson `
        -Path $badTlsReportPath `
        -Code 'bad-tls-report'
    $badTlsAggregate = Read-ProvenanceJson `
        -Path $badTlsAggregatePath `
        -Code 'bad-tls-aggregate'
    $badTlsSidecar.tls.alignment = 48
    $badTlsReport.tls.alignment = 48
    $badTlsAggregate.tlsLayout.dataAlignment = 48
    $badTlsAggregate.tlsLayout.items[0].alignment = 48
    $badTlsAggregate.modules[0].tls.alignment = 48
    Write-ProvenanceCanonicalJson `
        -Path $badTlsSidecarPath `
        -Value $badTlsSidecar
    Write-ProvenanceCanonicalJson `
        -Path $badTlsReportPath `
        -Value $badTlsReport
    Write-ProvenanceCanonicalJson `
        -Path $badTlsAggregatePath `
        -Value $badTlsAggregate
    Assert-Fails `
        -Message 'A non-power-of-two TLS alignment must fail.' `
        -Forbidden @($badTls.Root) `
        -Action {
            Invoke-Creator -Fixture $badTls
        }

    foreach ($blocked in @(
        @{ Name = 'body-cuts'; BodyCuts = 1 },
        @{ Name = 'unreported'; Unreported = 1 },
        @{ Name = 'unclassified'; Unclassified = 1 },
        @{ Name = 'missing-pc'; Pc = $false },
        @{ Name = 'entry-duplicate'; EntryMatches = 2 },
        @{ Name = 'entry-unresolved'; EntryMatches = 0 },
        @{ Name = 'report-drift'; AggregateBodyCutDelta = 1 },
        @{ Name = 'partition-drift'; AggregatePartitionDelta = 1 }
    )) {
        $parameters = @{
            Name = [string] $blocked.Name
        }
        foreach ($key in @(
            'BodyCuts',
            'Unreported',
            'Unclassified',
            'Pc',
            'EntryMatches',
            'AggregateBodyCutDelta',
            'AggregatePartitionDelta'
        )) {
            if ($blocked.ContainsKey($key)) {
                $parameters[$key] = $blocked[$key]
            }
        }
        $fixture = New-SyntheticFixture @parameters
        Assert-Fails `
            -Message "Blocked evidence '$($blocked.Name)' must fail." `
            -Forbidden @($fixture.Root) `
            -Action {
                Invoke-Creator -Fixture $fixture
            }
    }

    $target = Join-Path $scratch 'staged'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $unmanaged = Join-Path $target 'keep-me.txt'
    Set-TestContent -Path $unmanaged -Value 'unmanaged'
    & $stage `
        -SourceDir $valid.Source `
        -TargetDir $target `
        -RequiredProvenance '.generated-source-provenance.json' `
        -RuntimeManifest $valid.RuntimeManifest | Out-Null
    $stagedProvenance = Join-Path (
        $target
    ) '.generated-source-provenance.json'
    Assert-True `
        -Condition (Test-Path -LiteralPath $stagedProvenance -PathType Leaf) `
        -Message 'Provenance mode did not stage the provenance file.'
    $stagedBytes = [IO.File]::ReadAllBytes($stagedProvenance)
    $stagedTime = (
        Get-Item -LiteralPath $stagedProvenance
    ).LastWriteTimeUtc.Ticks
    Start-Sleep -Milliseconds 1100
    & $stage `
        -SourceDir $valid.Source `
        -TargetDir $target `
        -RequiredProvenance '.generated-source-provenance.json' `
        -RuntimeManifest $valid.RuntimeManifest | Out-Null
    Assert-True `
        -Condition (
            (Get-Item -LiteralPath $stagedProvenance).LastWriteTimeUtc.Ticks -eq
                $stagedTime
        ) `
        -Message 'A provenance staging no-op touched the provenance file.'

    $sourceProvenanceBytes = [IO.File]::ReadAllBytes($valid.Provenance)
    Set-TestContent -Path $valid.Provenance -Value '{'
    Assert-Fails `
        -Message 'Invalid provenance must fail before staging.' `
        -Forbidden @($valid.Root) `
        -Action {
            & $stage `
                -SourceDir $valid.Source `
                -TargetDir $target `
                -RequiredProvenance '.generated-source-provenance.json' `
                -RuntimeManifest $valid.RuntimeManifest | Out-Null
        }
    Assert-True `
        -Condition (
            [Linq.Enumerable]::SequenceEqual(
                $stagedBytes,
                [IO.File]::ReadAllBytes($stagedProvenance)
            ) -and
            (Get-Item -LiteralPath $stagedProvenance).LastWriteTimeUtc.Ticks -eq
                $stagedTime -and
            (Get-Content -LiteralPath $unmanaged -Raw) -ceq 'unmanaged'
        ) `
        -Message 'Failed provenance validation modified the target.'
    [IO.File]::WriteAllBytes($valid.Provenance, $sourceProvenanceBytes)

    Remove-Item -LiteralPath $valid.Provenance
    & $stage -SourceDir $valid.Source -TargetDir $target | Out-Null
    Assert-True `
        -Condition (
            -not (Test-Path -LiteralPath $stagedProvenance) -and
            (Test-Path -LiteralPath $unmanaged -PathType Leaf)
        ) `
        -Message (
            'Legacy staging did not remove stale managed provenance or ' +
            'preserve an unmanaged file.'
        )

    Write-Host 'Generated-source provenance synthetic tests passed.'
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
