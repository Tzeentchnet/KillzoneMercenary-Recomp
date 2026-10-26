# SPDX-License-Identifier: GPL-2.0-or-later

<#
.SYNOPSIS
    Creates deterministic local generated-source provenance.

.DESCRIPTION
    Inventories armrecomp per-module sidecars/reports, the aggregate compose
    report, generated registry, imports, C partitions, and headers. The output
    contains only normalized source-relative paths. It is validated before it
    replaces an existing provenance file.

.PARAMETER SourceRoot
    Generator-output root. Persisted paths are relative to this directory.

.PARAMETER RuntimeManifest
    Raw runtime manifest to identify by SHA-256 without copying its contents.

.PARAMETER GeneratorExecutable
    armrecomp executable to identify by SHA-256.

.PARAMETER CommandSpecFile
    JSON object containing exact normalized commands and all four recognized
    generation environment knobs. See docs/generated-source-provenance.md.

.PARAMETER AggregateReport
    Source-relative armrecomp compose .report.json path.

.PARAMETER EntryModuleId
    Explicit module ID selected by the entry policy.

.PARAMETER OutputFile
    Source-relative destination for the provenance JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $true, Position = 1)]
    [string] $RuntimeManifest,

    [Parameter(Mandatory = $true, Position = 2)]
    [string] $GeneratorExecutable,

    [Parameter(Mandatory = $true, Position = 3)]
    [string] $CommandSpecFile,

    [Parameter(Mandatory = $true, Position = 4)]
    [string] $AggregateReport,

    [Parameter(Mandatory = $true, Position = 5)]
    [string] $EntryModuleId,

    [Parameter(Mandatory = $true, Position = 6)]
    [string] $OutputFile,

    [string] $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..')
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GeneratedSourceProvenance.Common.ps1')

function New-ArtifactRecord {
    param(
        [string] $RelativePath,
        [string] $Source
    )

    $fullPath = Resolve-ProvenanceSourcePath `
        -SourceRoot $Source `
        -RelativePath $RelativePath
    return [pscustomobject][ordered]@{
        path = $RelativePath
        sha256 = Get-ProvenanceSha256 -Path $fullPath
    }
}

function Get-NamedTrapCount {
    param([object] $Report)

    [uint64] $total = 0
    foreach ($trap in @($Report.traps.kinds)) {
        $total += [uint64] $trap.count
    }
    return $total
}

$candidate = $null
try {
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $SourceRoot -PathType Container) `
        -Code 'source-root'
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $RuntimeManifest -PathType Leaf) `
        -Code 'runtime-manifest'
    Assert-ProvenanceCondition `
        -Condition (
            Test-Path -LiteralPath $GeneratorExecutable -PathType Leaf
        ) `
        -Code 'generator-executable'
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $CommandSpecFile -PathType Leaf) `
        -Code 'command-spec'
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceRelativePath -Value $AggregateReport) `
        -Code 'aggregate-report-path'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceRelativePath -Value $OutputFile) -and
            $OutputFile.EndsWith('.json', [StringComparison]::Ordinal) -and
            -not $OutputFile.EndsWith(
                '.report.json',
                [StringComparison]::Ordinal
            ) -and
            -not $OutputFile.EndsWith(
                '.module.json',
                [StringComparison]::Ordinal
            )
        ) `
        -Code 'output-path'
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceModuleId -Value $EntryModuleId) `
        -Code 'entry-module-id'

    $source = [IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $SourceRoot).ProviderPath
    ).TrimEnd('\')
    $repository = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $pinPath = Join-Path $repository 'config\framework.commit'
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $pinPath -PathType Leaf) `
        -Code 'framework-pin'
    $frameworkCommit = ([IO.File]::ReadAllText($pinPath)).Trim()
    Assert-ProvenanceCondition `
        -Condition ($frameworkCommit -cmatch '^[0-9a-f]{40}$') `
        -Code 'framework-pin'

    $commandSpec = Read-ProvenanceJson `
        -Path $CommandSpecFile `
        -Code 'command-spec-json'
    Test-ProvenanceExactProperties `
        -Value $commandSpec `
        -Names @('commands', 'environment') `
        -Code 'command-spec-shape'
    $commands = New-Object 'System.Collections.Generic.List[object]'
    foreach ($command in @($commandSpec.commands)) {
        Test-ProvenanceExactProperties `
            -Value $command `
            -Names @(
                'sequence',
                'phase',
                'moduleId',
                'executable',
                'arguments'
            ) `
            -Code 'command-shape'
        $arguments = @(
            @($command.arguments) | ForEach-Object { [string] $_ }
        )
        $commands.Add([pscustomobject][ordered]@{
            sequence = $command.sequence
            phase = [string] $command.phase
            moduleId = if ($null -eq $command.moduleId) {
                $null
            } else {
                [string] $command.moduleId
            }
            executable = [string] $command.executable
            arguments = $arguments
        })
    }
    $environment = New-Object 'System.Collections.Generic.List[object]'
    foreach ($knob in @($commandSpec.environment)) {
        Test-ProvenanceExactProperties `
            -Value $knob `
            -Names @('name', 'value') `
            -Code 'environment-shape'
        $environment.Add([pscustomobject][ordered]@{
            name = [string] $knob.name
            value = if ($null -eq $knob.value) {
                $null
            } else {
                [string] $knob.value
            }
        })
    }

    $sidecarPaths = @(
        Get-ChildItem -LiteralPath $source -File -Recurse -Force |
            Where-Object {
                $_.Name.EndsWith(
                    '.module.json',
                    [StringComparison]::Ordinal
                )
            } |
            ForEach-Object {
                Get-ProvenanceRelativePath `
                    -SourceRoot $source `
                    -Path $_.FullName
            }
    )
    $sidecarPaths = @(
        Get-ProvenanceSortedStrings -Values $sidecarPaths
    )
    Assert-ProvenanceCondition `
        -Condition ($sidecarPaths.Count -ge 1 -and $sidecarPaths.Count -le 64) `
        -Code 'module-count'

    $moduleById = New-Object (
        'System.Collections.Generic.Dictionary[string, object]'
    ) ([StringComparer]::Ordinal)
    foreach ($sidecarPath in $sidecarPaths) {
        $sidecar = Read-ProvenanceJson -Path (
            Resolve-ProvenanceSourcePath `
                -SourceRoot $source `
                -RelativePath $sidecarPath
        ) -Code 'sidecar-json'
        Assert-ProvenanceCondition `
            -Condition (
                (Test-ProvenanceModuleId -Value $sidecar.module.id) -and
                -not $moduleById.ContainsKey([string] $sidecar.module.id)
            ) `
            -Code 'module-id-collision'
        $base = $sidecarPath.Substring(
            0,
            $sidecarPath.Length - '.module.json'.Length
        )
        $reportJsonPath = "$base.report.json"
        $reportTextPath = "$base.report.txt"
        $report = Read-ProvenanceJson -Path (
            Resolve-ProvenanceSourcePath `
                -SourceRoot $source `
                -RelativePath $reportJsonPath
        ) -Code 'module-report-json'

        $partitions = New-Object 'System.Collections.Generic.List[object]'
        $reportPartitions = @($report.partitions.items)
        for ($index = 0; $index -lt $reportPartitions.Count; $index++) {
            $item = $reportPartitions[$index]
            $unit = [string] $item.unit
            $path = if ($unit -ceq 'main') {
                "$base.c"
            } elseif ($unit -cmatch '^part-[0-9]{3}$') {
                "$base" + '_' + $unit.Substring(5) + '.c'
            } else {
                Stop-ProvenanceValidation -Code 'partition-unit'
            }
            $partitions.Add([pscustomobject][ordered]@{
                unit = $unit
                path = $path
                sha256 = Get-ProvenanceSha256 -Path (
                    Resolve-ProvenanceSourcePath `
                        -SourceRoot $source `
                        -RelativePath $path
                )
                functions = $item.functions
                instructions = $item.instructions
                firstKey = [string] $item.firstKey
                lastKey = [string] $item.lastKey
            })
        }
        $module = [pscustomobject][ordered]@{
            id = [string] $sidecar.module.id
            sidecar = New-ArtifactRecord `
                -RelativePath $sidecarPath `
                -Source $source
            reportJson = New-ArtifactRecord `
                -RelativePath $reportJsonPath `
                -Source $source
            reportText = New-ArtifactRecord `
                -RelativePath $reportTextPath `
                -Source $source
            tls = [pscustomobject][ordered]@{
                present = [bool] $sidecar.tls.present
                resolved = [bool] $sidecar.tls.resolved
                address = [string] $sidecar.tls.address
                fileSize = $sidecar.tls.fileSize
                memorySize = $sidecar.tls.memorySize
                alignment = $sidecar.tls.alignment
            }
            partitions = $partitions.ToArray()
            readiness = [pscustomobject][ordered]@{
                structuralReady = [bool] $report.structuralReady
                productionReady = [bool] $report.productionReady
                pcInstrumentation = [bool] $report.instrumentation.pc
                bodyCuts = $report.instructions.bodyCuts
                unreportedPartitions = $report.partitions.unreported
                unclassifiedTraps = $report.traps.unclassified
                classifiedNamedTraps = Get-NamedTrapCount -Report $report
            }
        }
        $moduleById.Add([string] $module.id, [pscustomobject]@{
            Record = $module
            Base = $base
            Report = $report
        })
    }
    $moduleIds = @(
        Get-ProvenanceSortedStrings -Values @($moduleById.Keys)
    )
    $modules = @(
        $moduleIds | ForEach-Object { $moduleById[$_].Record }
    )

    $aggregateDocument = Read-ProvenanceJson -Path (
        Resolve-ProvenanceSourcePath `
            -SourceRoot $source `
            -RelativePath $AggregateReport
    ) -Code 'aggregate-report-json'
    Assert-ProvenanceCondition `
        -Condition $AggregateReport.EndsWith(
            '.report.json',
            [StringComparison]::Ordinal
        ) `
        -Code 'aggregate-report-name'
    $registryBase = $AggregateReport.Substring(
        0,
        $AggregateReport.Length - '.report.json'.Length
    )
    $registrySource = "$registryBase.c"
    $registryHeader = "$registryBase.h"
    $aggregateText = "$registryBase.report.txt"

    $blockers = New-Object 'System.Collections.Generic.List[string]'
    if (@($modules | Where-Object {
        -not [bool] $_.readiness.structuralReady
    }).Count -gt 0) {
        $blockers.Add('module-not-structurally-ready')
    }
    if (-not [bool] $aggregateDocument.structuralReady) {
        $blockers.Add('aggregate-not-structurally-ready')
    }
    if (@($modules | Where-Object {
        [uint64] $_.readiness.bodyCuts -gt 0
    }).Count -gt 0 -or
        [uint64] $aggregateDocument.totals.instructions.bodyCuts -gt 0) {
        $blockers.Add('body-cuts')
    }
    if (@($modules | Where-Object {
        [uint64] $_.readiness.unreportedPartitions -gt 0
    }).Count -gt 0 -or
        [uint64] $aggregateDocument.totals.partitions.unreported -gt 0) {
        $blockers.Add('unreported-partitions')
    }
    if (@($modules | Where-Object {
        [uint64] $_.readiness.unclassifiedTraps -gt 0
    }).Count -gt 0 -or
        [uint64] $aggregateDocument.totals.traps.unclassified -gt 0) {
        $blockers.Add('unclassified-traps')
    }
    if (@($modules | Where-Object {
        -not [bool] $_.readiness.pcInstrumentation
    }).Count -gt 0 -or
        -not [bool] $aggregateDocument.instrumentation.pc) {
        $blockers.Add('missing-pc-instrumentation')
    }
    if (@($moduleById.Values | Where-Object {
        -not [bool] $_.Report.instrumentation.functionEntry
    }).Count -gt 0 -or
        -not [bool] $aggregateDocument.instrumentation.functionEntry) {
        $blockers.Add('missing-function-entry-instrumentation')
    }
    if ([string] $aggregateDocument.entryModuleId -cne $EntryModuleId -or
        [string] $aggregateDocument.entry.moduleId -cne $EntryModuleId) {
        $blockers.Add('entry-module-mismatch')
    }
    if ([uint64] $aggregateDocument.entry.matches -ne 1 -or
        -not [bool] $aggregateDocument.entryEligible) {
        $blockers.Add('duplicate-or-unresolved-entry')
    }
    if ([uint64] $aggregateDocument.moduleCount -ne $modules.Count) {
        $blockers.Add('module-count-mismatch')
    }
    $sortedBlockers = @(
        Get-ProvenanceSortedStrings -Values $blockers.ToArray()
    )
    [uint64] $namedTrapCount = 0
    foreach ($module in $modules) {
        $namedTrapCount += [uint64] $module.readiness.classifiedNamedTraps
    }

    $aggregate = [pscustomobject][ordered]@{
        reportJson = New-ArtifactRecord `
            -RelativePath $AggregateReport `
            -Source $source
        reportText = New-ArtifactRecord `
            -RelativePath $aggregateText `
            -Source $source
        registrySource = New-ArtifactRecord `
            -RelativePath $registrySource `
            -Source $source
        registryHeader = New-ArtifactRecord `
            -RelativePath $registryHeader `
            -Source $source
        moduleCount = $aggregateDocument.moduleCount
        tlsLayout = [pscustomobject][ordered]@{
            moduleCount = $aggregateDocument.tlsLayout.moduleCount
            dataSize = $aggregateDocument.tlsLayout.dataSize
            dataAlignment = $aggregateDocument.tlsLayout.dataAlignment
            items = @(
                @($aggregateDocument.tlsLayout.items) | ForEach-Object {
                    [pscustomobject][ordered]@{
                        moduleId = [string] $_.moduleId
                        descriptorIndex = $_.descriptorIndex
                        order = $_.order
                        offset = $_.offset
                        alignment = $_.alignment
                    }
                }
            )
        }
        structuralReady = [bool] $aggregateDocument.structuralReady
        entryEligible = [bool] $aggregateDocument.entryEligible
        productionReady = [bool] $aggregateDocument.productionReady
        pcInstrumentation = [bool] $aggregateDocument.instrumentation.pc
        entryMatches = $aggregateDocument.entry.matches
        classifiedNamedTraps = $namedTrapCount
        blockers = $sortedBlockers
    }

    $classification = New-Object (
        'System.Collections.Generic.Dictionary[string, object]'
    ) ([StringComparer]::Ordinal)
    foreach ($moduleId in $moduleIds) {
        $item = $moduleById[$moduleId]
        $classification.Add(
            ([string] $item.Base + '.c'),
            [pscustomobject]@{
                Kind = 'module-source'
                ModuleId = $moduleId
            }
        )
        foreach ($partition in @($item.Record.partitions)) {
            if ($partition.unit -cne 'main') {
                $classification.Add(
                    [string] $partition.path,
                    [pscustomobject]@{
                        Kind = 'module-partition'
                        ModuleId = $moduleId
                    }
                )
            }
        }
        $classification.Add(
            ([string] $item.Base + '.h'),
            [pscustomobject]@{
                Kind = 'module-header'
                ModuleId = $moduleId
            }
        )
        $importPrefix = [string] $item.Base + '_imports/'
        $imports = @(
            Get-ChildItem -LiteralPath $source -File -Recurse -Force |
                ForEach-Object {
                    Get-ProvenanceRelativePath `
                        -SourceRoot $source `
                        -Path $_.FullName
                } |
                Where-Object {
                    $_.StartsWith(
                        $importPrefix,
                        [StringComparison]::Ordinal
                    ) -and $_.EndsWith(
                        '.c',
                        [StringComparison]::Ordinal
                    )
                }
        )
        foreach ($importPath in (
            Get-ProvenanceSortedStrings -Values $imports
        )) {
            $classification.Add(
                $importPath,
                [pscustomobject]@{
                    Kind = 'import-source'
                    ModuleId = $moduleId
                }
            )
        }
    }
    $classification.Add(
        $registrySource,
        [pscustomobject]@{
            Kind = 'registry-source'
            ModuleId = $null
        }
    )
    $classification.Add(
        $registryHeader,
        [pscustomobject]@{
            Kind = 'registry-header'
            ModuleId = $null
        }
    )

    $generatedPaths = @(
        Get-ChildItem -LiteralPath $source -File -Recurse -Force |
            Where-Object {
                $_.Extension -ceq '.c' -or $_.Extension -ceq '.h'
            } |
            ForEach-Object {
                Get-ProvenanceRelativePath `
                    -SourceRoot $source `
                    -Path $_.FullName
            }
    )
    $generatedPaths = @(
        Get-ProvenanceSortedStrings -Values $generatedPaths
    )
    Assert-ProvenanceCondition `
        -Condition ($generatedPaths.Count -eq $classification.Count) `
        -Code 'generated-inventory-count'
    $generatedFiles = New-Object 'System.Collections.Generic.List[object]'
    foreach ($path in $generatedPaths) {
        Assert-ProvenanceCondition `
            -Condition $classification.ContainsKey($path) `
            -Code 'unclassified-generated-file'
        $kind = $classification[$path]
        $generatedFiles.Add([pscustomobject][ordered]@{
            path = $path
            sha256 = Get-ProvenanceSha256 -Path (
                Resolve-ProvenanceSourcePath `
                    -SourceRoot $source `
                    -RelativePath $path
            )
            kind = [string] $kind.Kind
            moduleId = if ($null -eq $kind.ModuleId) {
                $null
            } else {
                [string] $kind.ModuleId
            }
        })
    }

    $manifest = [pscustomobject][ordered]@{
        schemaVersion = 2
        entryPolicyVersion = 1
        framework = [pscustomobject][ordered]@{
            commit = $frameworkCommit
        }
        generator = [pscustomobject][ordered]@{
            name = 'armrecomp'
            executableSha256 = Get-ProvenanceSha256 `
                -Path $GeneratorExecutable
            moduleSidecarSchemaVersion = 4
            moduleReportSchemaVersion = 4
            composeReportSchemaVersion = 4
            commands = $commands.ToArray()
            environment = $environment.ToArray()
        }
        runtimeManifest = [pscustomobject][ordered]@{
            sha256 = Get-ProvenanceSha256 -Path $RuntimeManifest
        }
        entryModuleId = $EntryModuleId
        modules = $modules
        aggregate = $aggregate
        generatedFiles = $generatedFiles.ToArray()
    }

    $outputPath = Resolve-ProvenanceSourcePath `
        -SourceRoot $source `
        -RelativePath $OutputFile
    $candidate = Join-Path $source (
        '.generated-source-provenance-candidate-' +
        [Guid]::NewGuid().ToString('N') +
        '.json'
    )
    Write-ProvenanceCanonicalJson -Path $candidate -Value $manifest

    $validator = Join-Path $PSScriptRoot 'Test-GeneratedSourceProvenance.ps1'
    & $validator `
        -ProvenanceFile $candidate `
        -SourceRoot $source `
        -RuntimeManifest $RuntimeManifest `
        -RepositoryRoot $repository `
        -GeneratorExecutable $GeneratorExecutable `
        -Quiet

    $candidateBytes = [IO.File]::ReadAllBytes($candidate)
    $unchanged = $false
    if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        $existingBytes = [IO.File]::ReadAllBytes($outputPath)
        $unchanged = [Linq.Enumerable]::SequenceEqual(
            $candidateBytes,
            $existingBytes
        )
    }
    if (-not $unchanged) {
        $parent = Split-Path -Parent $outputPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [IO.File]::WriteAllBytes($outputPath, $candidateBytes)
    }
    Write-Host 'Generated-source provenance created.'
} catch {
    if ($_.Exception.Message.StartsWith(
        'Generated-source provenance validation failed',
        [StringComparison]::Ordinal
    )) {
        throw
    }
    Stop-ProvenanceValidation -Code 'unexpected-creation-error'
} finally {
    if ($null -ne $candidate -and
        (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Remove-Item -LiteralPath $candidate -Force
    }
}
