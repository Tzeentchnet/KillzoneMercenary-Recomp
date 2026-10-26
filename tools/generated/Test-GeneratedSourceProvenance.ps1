# SPDX-License-Identifier: GPL-2.0-or-later

<#
.SYNOPSIS
    Validates a local generated-source provenance manifest.

.DESCRIPTION
    Re-hashes the raw runtime manifest, framework pin, generator identity when
    supplied, module reports and sidecars, aggregate compose report, registry,
    and every generated C/header file. Validation is deliberately silent about
    local paths and hashes.

.PARAMETER ProvenanceFile
    The local provenance manifest to validate.

.PARAMETER SourceRoot
    The generator-output root to which all persisted paths are relative.

.PARAMETER RuntimeManifest
    The raw runtime manifest whose byte identity is recorded by provenance.

.PARAMETER RepositoryRoot
    Repository containing config/framework.commit.

.PARAMETER GeneratorExecutable
    Optional armrecomp executable to re-hash against its recorded identity.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $ProvenanceFile,

    [Parameter(Mandatory = $true, Position = 1)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $true, Position = 2)]
    [string] $RuntimeManifest,

    [string] $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..')
    ),

    [string] $GeneratorExecutable,

    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GeneratedSourceProvenance.Common.ps1')

function Test-BooleanValue {
    param(
        [object] $Value,
        [string] $Code
    )

    Assert-ProvenanceCondition `
        -Condition ($Value -is [bool]) `
        -Code $Code
}

function Test-IntegerValue {
    param(
        [object] $Value,
        [uint64] $Maximum,
        [string] $Code
    )

    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger -Value $Value) -and
            [decimal] $Value -ge 0 -and
            [decimal] $Value -le [decimal] $Maximum
        ) `
        -Code $Code
}

function Test-ProvenancePowerOfTwo {
    param([object] $Value)

    if (-not (Test-ProvenanceInteger -Value $Value) -or
        [decimal] $Value -lt 1 -or
        [decimal] $Value -gt [decimal] ([uint32]::MaxValue)) {
        return $false
    }
    [uint64] $number = [uint64] $Value
    return ($number -band ($number - 1)) -eq 0
}

function Get-ArtifactRecord {
    param(
        [string] $Path,
        [string] $Source
    )

    return [pscustomobject][ordered]@{
        path = $Path
        sha256 = Get-ProvenanceSha256 -Path (
            Resolve-ProvenanceSourcePath `
                -SourceRoot $Source `
                -RelativePath $Path
        )
    }
}

function Test-ModuleEvidence {
    param(
        [object] $Module,
        [string] $Source,
        [Collections.Generic.Dictionary[string, object]] $GeneratedExpected
    )

    Test-ProvenanceExactProperties `
        -Value $Module `
        -Names @(
            'id',
            'sidecar',
            'reportJson',
            'reportText',
            'tls',
            'partitions',
            'readiness'
        ) `
        -Code 'module-shape'
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceModuleId -Value $Module.id) `
        -Code 'module-id'
    Test-ProvenanceArtifact `
        -Artifact $Module.sidecar `
        -SourceRoot $Source `
        -Code 'sidecar-artifact'
    Test-ProvenanceArtifact `
        -Artifact $Module.reportJson `
        -SourceRoot $Source `
        -Code 'module-report-artifact'
    Test-ProvenanceArtifact `
        -Artifact $Module.reportText `
        -SourceRoot $Source `
        -Code 'module-text-report-artifact'

    $sidecarPath = [string] $Module.sidecar.path
    Assert-ProvenanceCondition `
        -Condition $sidecarPath.EndsWith(
            '.module.json',
            [StringComparison]::Ordinal
        ) `
        -Code 'sidecar-name'
    $base = $sidecarPath.Substring(
        0,
        $sidecarPath.Length - '.module.json'.Length
    )
    Assert-ProvenanceCondition `
        -Condition (
            [string] $Module.reportJson.path -ceq "$base.report.json" -and
            [string] $Module.reportText.path -ceq "$base.report.txt"
        ) `
        -Code 'module-report-name'

    $sidecar = Read-ProvenanceJson -Path (
        Resolve-ProvenanceSourcePath `
            -SourceRoot $Source `
            -RelativePath $Module.sidecar.path
    ) -Code 'sidecar-json'
    Test-ProvenanceExactProperties `
        -Value $sidecar `
        -Names @(
            'schemaVersion',
            'abiVersion',
            'generator',
            'module',
            'ranges',
            'dispatch',
            'entry',
            'tls',
            'functionImports',
            'exports',
            'variableImports',
            'report'
        ) `
        -Code 'sidecar-schema'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger -Value $sidecar.schemaVersion) -and
            (Test-ProvenanceInteger -Value $sidecar.abiVersion) -and
            [uint64] $sidecar.schemaVersion -eq 4 -and
            [uint64] $sidecar.abiVersion -eq 4 -and
            $sidecar.generator -ceq 'armrecomp'
        ) `
        -Code 'sidecar-version'
    Test-ProvenanceExactProperties `
        -Value $sidecar.module `
        -Names @('id', 'name', 'descriptorSymbol') `
        -Code 'sidecar-module'
    Assert-ProvenanceCondition `
        -Condition ([string] $sidecar.module.id -ceq [string] $Module.id) `
        -Code 'sidecar-module-id'
    Test-ProvenanceExactProperties `
        -Value $sidecar.report `
        -Names @(
            'schemaVersion',
            'structuralReady',
            'productionReady',
            'strictUnsupported',
            'pcInstrumentation',
            'unclassifiedTrapCount'
        ) `
        -Code 'sidecar-report-summary'
    Test-ProvenanceExactProperties `
        -Value $sidecar.entry `
        -Names @(
            'present',
            'rawAddress',
            'dispatchKey',
            'function',
            'resolved'
        ) `
        -Code 'sidecar-entry'
    Test-ProvenanceExactProperties `
        -Value $sidecar.tls `
        -Names @(
            'present',
            'resolved',
            'address',
            'fileSize',
            'memorySize',
            'alignment'
        ) `
        -Code 'sidecar-tls'
    Test-ProvenanceExactProperties `
        -Value $Module.tls `
        -Names @(
            'present',
            'resolved',
            'address',
            'fileSize',
            'memorySize',
            'alignment'
        ) `
        -Code 'module-tls'
    Test-ProvenanceExactProperties `
        -Value $sidecar.functionImports `
        -Names @('count', 'items') `
        -Code 'sidecar-function-imports'
    $functionImports = @($sidecar.functionImports.items)
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger -Value $sidecar.functionImports.count) -and
            [uint64] $sidecar.functionImports.count -eq
                [uint64] $functionImports.Count
        ) `
        -Code 'sidecar-function-import-count'
    $functionImportKeys = New-Object (
        'System.Collections.Generic.HashSet[string]'
    ) ([StringComparer]::Ordinal)
    $functionImportSites = New-Object (
        'System.Collections.Generic.HashSet[string]'
    ) ([StringComparer]::Ordinal)
    $functionImportSlots = New-Object (
        'System.Collections.Generic.HashSet[string]'
    ) ([StringComparer]::Ordinal)
    foreach ($functionImport in $functionImports) {
        Test-ProvenanceExactProperties `
            -Value $functionImport `
            -Names @(
                'key',
                'stubAddress',
                'targetSite',
                'libraryNid',
                'functionNid',
                'name',
                'symbol',
                'targetSlot',
                'strictUnsupported'
            ) `
            -Code 'sidecar-function-import'
        $hexValues = @(
            [string] $functionImport.key,
            [string] $functionImport.stubAddress,
            [string] $functionImport.targetSite,
            [string] $functionImport.libraryNid,
            [string] $functionImport.functionNid
        )
        Assert-ProvenanceCondition `
            -Condition (
                @($hexValues | Where-Object {
                    $_ -cnotmatch '^0x[0-9A-F]{8}$'
                }).Count -eq 0 -and
                $functionImport.strictUnsupported -is [bool] -and
                ([string] $functionImport.symbol) -cmatch
                    '^vita_hle_[A-Za-z0-9_]+$' -and
                ([string] $functionImport.targetSlot) -ceq (
                    'vita_import_target_{0}_{1}' -f
                        [string] $Module.id,
                        ([string] $functionImport.targetSite).Substring(2)
                ) -and
                ($null -eq $functionImport.name -or
                    -not [string]::IsNullOrEmpty(
                        [string] $functionImport.name
                    )) -and
                (-not [bool] $functionImport.strictUnsupported -or
                    $null -ne $functionImport.name)
            ) `
            -Code 'sidecar-function-import-value'
        $key = [Convert]::ToUInt32(
            ([string] $functionImport.key).Substring(2),
            16
        )
        $stub = [Convert]::ToUInt32(
            ([string] $functionImport.stubAddress).Substring(2),
            16
        )
        $site = [Convert]::ToUInt32(
            ([string] $functionImport.targetSite).Substring(2),
            16
        )
        $matchingDispatch = @(
            @($sidecar.dispatch.entries) | Where-Object {
                [string] $_.key -ceq [string] $functionImport.key -and
                [string] $_.kind -ceq 'functionImport' -and
                [string] $_.libraryNid -ceq
                    [string] $functionImport.libraryNid -and
                [string] $_.functionNid -ceq
                    [string] $functionImport.functionNid -and
                [string] $_.symbol -ceq [string] $functionImport.symbol
            }
        )
        Assert-ProvenanceCondition `
            -Condition (
                ($key -band 0xFFFFFFFE) -eq $stub -and
                ($stub -band 1) -eq 0 -and
                ($site -band 3) -eq 0 -and
                $functionImportKeys.Add([string] $functionImport.key) -and
                $functionImportSites.Add(
                    [string] $functionImport.targetSite
                ) -and
                $functionImportSlots.Add(
                    [string] $functionImport.targetSlot
                ) -and
                $matchingDispatch.Count -eq 1
            ) `
            -Code 'sidecar-function-import-agreement'
    }
    foreach ($value in @(
        $sidecar.entry.present,
        $sidecar.entry.resolved,
        $sidecar.tls.present,
        $sidecar.tls.resolved,
        $sidecar.report.structuralReady,
        $sidecar.report.productionReady,
        $sidecar.report.strictUnsupported,
        $sidecar.report.pcInstrumentation
    )) {
        Test-BooleanValue -Value $value -Code 'sidecar-boolean'
    }
    foreach ($value in @(
        $sidecar.tls.fileSize,
        $sidecar.tls.memorySize,
        $sidecar.tls.alignment
    )) {
        Test-IntegerValue `
            -Value $value `
            -Maximum ([uint32]::MaxValue) `
            -Code 'sidecar-tls-value'
    }
    Assert-ProvenanceCondition `
        -Condition (
            ([string] $sidecar.entry.rawAddress) -cmatch
                '^0x[0-9A-F]{8}$' -and
            ([string] $sidecar.entry.dispatchKey) -cmatch
                '^0x[0-9A-F]{8}$' -and
            ([string] $sidecar.tls.address) -cmatch
                '^0x[0-9A-F]{8}$' -and
            (-not [bool] $sidecar.entry.present -or
                [bool] $sidecar.entry.resolved) -and
            (-not [bool] $sidecar.tls.present -or
                [bool] $sidecar.tls.resolved) -and
            [uint64] $sidecar.tls.fileSize -le
                [uint64] $sidecar.tls.memorySize -and
            (
                (
                    [bool] $sidecar.tls.present -and
                    [uint64] $sidecar.tls.memorySize -gt 0 -and
                    (Test-ProvenancePowerOfTwo `
                        -Value $sidecar.tls.alignment)
                ) -or
                (
                    -not [bool] $sidecar.tls.present -and
                    -not [bool] $sidecar.tls.resolved -and
                    [string] $sidecar.tls.address -ceq '0x00000000' -and
                    [uint64] $sidecar.tls.fileSize -eq 0 -and
                    [uint64] $sidecar.tls.memorySize -eq 0 -and
                    [uint64] $sidecar.tls.alignment -eq 0
                )
            ) -and
            (ConvertTo-ProvenanceCanonicalJson -Value $Module.tls) -ceq
                (ConvertTo-ProvenanceCanonicalJson -Value $sidecar.tls)
        ) `
        -Code 'unresolved-module-metadata'

    $report = Read-ProvenanceJson -Path (
        Resolve-ProvenanceSourcePath `
            -SourceRoot $Source `
            -RelativePath $Module.reportJson.path
    ) -Code 'module-report-json'
    Test-ProvenanceExactProperties `
        -Value $report `
        -Names @(
            'schemaVersion',
            'generator',
            'module',
            'strictUnsupported',
            'structuralReady',
            'productionReady',
            'instrumentation',
            'entry',
            'tls',
            'functions',
            'instructions',
            'traps',
            'partitions'
        ) `
        -Code 'module-report-schema'
    Test-ProvenanceExactProperties `
        -Value $report.module `
        -Names @('id', 'name') `
        -Code 'module-report-module'
    Test-ProvenanceExactProperties `
        -Value $report.instrumentation `
        -Names @('functionEntry', 'pc') `
        -Code 'module-instrumentation'
    Test-ProvenanceExactProperties `
        -Value $report.entry `
        -Names @('present', 'rawAddress', 'dispatchKey', 'resolved') `
        -Code 'module-entry'
    Test-ProvenanceExactProperties `
        -Value $report.tls `
        -Names @(
            'present',
            'resolved',
            'address',
            'fileSize',
            'memorySize',
            'alignment'
        ) `
        -Code 'module-tls-report'
    Test-ProvenanceExactProperties `
        -Value $report.functions `
        -Names @('emitted', 'discovered', 'dropped', 'promotedWeakRoots') `
        -Code 'module-functions'
    Test-ProvenanceExactProperties `
        -Value $report.instructions `
        -Names @('total', 'translated', 'trapped', 'bodyCuts') `
        -Code 'module-instructions'
    Test-ProvenanceExactProperties `
        -Value $report.traps `
        -Names @('total', 'classified', 'unclassified', 'other', 'kinds') `
        -Code 'module-traps'
    Test-ProvenanceExactProperties `
        -Value $report.partitions `
        -Names @('unreported', 'items') `
        -Code 'module-partitions'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger -Value $report.schemaVersion) -and
            [uint64] $report.schemaVersion -eq 4 -and
            $report.generator -ceq 'armrecomp' -and
            [string] $report.module.id -ceq [string] $Module.id -and
            [string] $report.module.name -ceq [string] $sidecar.module.name -and
            $report.strictUnsupported -eq $true -and
            $report.traps.kinds -is [Array]
        ) `
        -Code 'module-report-identity'
    Assert-ProvenanceCondition `
        -Condition (
            ([string] $report.entry.rawAddress) -cmatch
                '^0x[0-9A-F]{8}$' -and
            ([string] $report.entry.dispatchKey) -cmatch
                '^0x[0-9A-F]{8}$' -and
            $report.entry.present -eq $sidecar.entry.present -and
            $report.entry.resolved -eq $sidecar.entry.resolved -and
            [string] $report.entry.rawAddress -ceq
                [string] $sidecar.entry.rawAddress -and
            [string] $report.entry.dispatchKey -ceq
                [string] $sidecar.entry.dispatchKey -and
            (ConvertTo-ProvenanceCanonicalJson -Value $report.tls) -ceq
                (ConvertTo-ProvenanceCanonicalJson -Value $sidecar.tls) -and
            (-not [bool] $report.entry.present -or
                [bool] $report.entry.resolved)
        ) `
        -Code 'unresolved-entry'

    foreach ($value in @(
        $report.structuralReady,
        $report.productionReady,
        $report.instrumentation.functionEntry,
        $report.instrumentation.pc,
        $report.entry.present,
        $report.entry.resolved,
        $report.tls.present,
        $report.tls.resolved
    )) {
        Test-BooleanValue -Value $value -Code 'module-report-boolean'
    }
    foreach ($value in @(
        $report.functions.emitted,
        $report.functions.discovered,
        $report.functions.dropped,
        $report.functions.promotedWeakRoots,
        $report.instructions.total,
        $report.instructions.translated,
        $report.instructions.trapped,
        $report.instructions.bodyCuts,
        $report.traps.total,
        $report.traps.classified,
        $report.traps.unclassified,
        $report.traps.other,
        $report.partitions.unreported
    )) {
        Test-IntegerValue `
            -Value $value `
            -Maximum ([uint64]::MaxValue) `
            -Code 'module-report-count'
    }
    Assert-ProvenanceCondition `
        -Condition (
            [uint64] $report.instructions.translated +
                [uint64] $report.instructions.trapped -eq
                [uint64] $report.instructions.total -and
            [uint64] $report.instructions.trapped -eq
                [uint64] $report.traps.total -and
            [uint64] $report.traps.total -eq
                [uint64] $report.traps.classified +
                [uint64] $report.traps.unclassified
        ) `
        -Code 'module-report-arithmetic'
    $expectedModuleProduction = (
        [uint64] $report.traps.total -eq 0 -and
        [uint64] $report.instructions.bodyCuts -eq 0 -and
        [uint64] $report.partitions.unreported -eq 0
    )
    Assert-ProvenanceCondition `
        -Condition (
            [bool] $report.productionReady -eq $expectedModuleProduction
        ) `
        -Code 'module-production-readiness'

    $trapKinds = @($report.traps.kinds)
    $trapNames = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal
    )
    [uint64] $namedTrapCount = 0
    [uint64] $previousCount = [uint64]::MaxValue
    $previousName = ''
    foreach ($trap in $trapKinds) {
        Test-ProvenanceExactProperties `
            -Value $trap `
            -Names @('kind', 'count') `
            -Code 'trap-kind-shape'
        Assert-ProvenanceCondition `
            -Condition (
                $trap.kind -is [string] -and
                -not [string]::IsNullOrWhiteSpace([string] $trap.kind) -and
                ([string] $trap.kind) -cmatch '^[ -~]+$' -and
                $trapNames.Add([string] $trap.kind)
            ) `
            -Code 'trap-kind'
        Test-IntegerValue `
            -Value $trap.count `
            -Maximum ([uint64]::MaxValue) `
            -Code 'trap-count'
        Assert-ProvenanceCondition `
            -Condition ([uint64] $trap.count -gt 0) `
            -Code 'trap-count'
        if ([uint64] $trap.count -gt $previousCount -or
            ([uint64] $trap.count -eq $previousCount -and
                [StringComparer]::Ordinal.Compare(
                    $previousName,
                    [string] $trap.kind
                ) -ge 0)) {
            Stop-ProvenanceValidation -Code 'trap-order'
        }
        $previousCount = [uint64] $trap.count
        $previousName = [string] $trap.kind
        $namedTrapCount += [uint64] $trap.count
    }
    Assert-ProvenanceCondition `
        -Condition (
            [uint64] $report.traps.other -eq 0 -and
            $namedTrapCount -eq [uint64] $report.traps.classified
        ) `
        -Code 'unnamed-classified-traps'

    Test-ProvenanceExactProperties `
        -Value $Module.readiness `
        -Names @(
            'structuralReady',
            'productionReady',
            'pcInstrumentation',
            'bodyCuts',
            'unreportedPartitions',
            'unclassifiedTraps',
            'classifiedNamedTraps'
        ) `
        -Code 'module-readiness-shape'
    foreach ($value in @(
        $Module.readiness.structuralReady,
        $Module.readiness.productionReady,
        $Module.readiness.pcInstrumentation
    )) {
        Test-BooleanValue -Value $value -Code 'module-readiness-boolean'
    }
    foreach ($value in @(
        $Module.readiness.bodyCuts,
        $Module.readiness.unreportedPartitions,
        $Module.readiness.unclassifiedTraps,
        $Module.readiness.classifiedNamedTraps
    )) {
        Test-IntegerValue `
            -Value $value `
            -Maximum ([uint64]::MaxValue) `
            -Code 'module-readiness-count'
    }
    Assert-ProvenanceCondition `
        -Condition (
            $Module.readiness.structuralReady -eq
                $report.structuralReady -and
            $Module.readiness.productionReady -eq
                $report.productionReady -and
            $Module.readiness.pcInstrumentation -eq
                $report.instrumentation.pc -and
            [uint64] $Module.readiness.bodyCuts -eq
                [uint64] $report.instructions.bodyCuts -and
            [uint64] $Module.readiness.unreportedPartitions -eq
                [uint64] $report.partitions.unreported -and
            [uint64] $Module.readiness.unclassifiedTraps -eq
                [uint64] $report.traps.unclassified -and
            [uint64] $Module.readiness.classifiedNamedTraps -eq
                $namedTrapCount
        ) `
        -Code 'module-readiness-drift'
    Assert-ProvenanceCondition `
        -Condition (
            $sidecar.report.schemaVersion -eq $report.schemaVersion -and
            $sidecar.report.structuralReady -eq $report.structuralReady -and
            $sidecar.report.productionReady -eq $report.productionReady -and
            $sidecar.report.strictUnsupported -eq
                $report.strictUnsupported -and
            $sidecar.report.pcInstrumentation -eq
                $report.instrumentation.pc -and
            [uint64] $sidecar.report.unclassifiedTrapCount -eq
                [uint64] $report.traps.unclassified
        ) `
        -Code 'sidecar-report-drift'

    $partitionRecords = @($Module.partitions)
    $reportPartitions = @($report.partitions.items)
    Assert-ProvenanceCondition `
        -Condition (
            $Module.partitions -is [Array] -and
            $report.partitions.items -is [Array] -and
            $partitionRecords.Count -eq $reportPartitions.Count
        ) `
        -Code 'partition-count-drift'
    $partitionPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    $GeneratedExpected.Add(
        "$base.c",
        [pscustomobject]@{
            Kind = 'module-source'
            ModuleId = [string] $Module.id
        }
    )
    $partitionMode = ''
    for ($index = 0; $index -lt $reportPartitions.Count; $index++) {
        $reportPartition = $reportPartitions[$index]
        $record = $partitionRecords[$index]
        Test-ProvenanceExactProperties `
            -Value $reportPartition `
            -Names @(
                'unit',
                'functions',
                'instructions',
                'firstKey',
                'lastKey'
            ) `
            -Code 'report-partition-shape'
        Test-ProvenanceExactProperties `
            -Value $record `
            -Names @(
                'unit',
                'path',
                'sha256',
                'functions',
                'instructions',
                'firstKey',
                'lastKey'
            ) `
            -Code 'partition-shape'
        foreach ($value in @(
            $record.functions,
            $record.instructions,
            $reportPartition.functions,
            $reportPartition.instructions
        )) {
            Test-IntegerValue `
                -Value $value `
                -Maximum ([uint32]::MaxValue) `
                -Code 'partition-count'
        }
        Assert-ProvenanceCondition `
            -Condition (
                ([string] $record.firstKey) -cmatch
                    '^0x[0-9A-F]{8}$' -and
                ([string] $record.lastKey) -cmatch
                    '^0x[0-9A-F]{8}$'
            ) `
            -Code 'partition-key'
        $expectedUnit = [string] $reportPartition.unit
        if ($expectedUnit -ceq 'main') {
            Assert-ProvenanceCondition `
                -Condition (
                    $partitionMode -cne 'parts' -and
                    $reportPartitions.Count -eq 1
                ) `
                -Code 'partition-order'
            $partitionMode = 'main'
        } else {
            if ([string]::IsNullOrEmpty($partitionMode)) {
                $partitionMode = 'parts'
            }
            Assert-ProvenanceCondition `
                -Condition (
                    $partitionMode -ceq 'parts' -and
                    $expectedUnit -ceq ('part-{0:d3}' -f $index)
                ) `
                -Code 'partition-order'
        }
        Assert-ProvenanceCondition `
            -Condition (
                [string] $record.unit -ceq $expectedUnit
            ) `
            -Code 'partition-order'
        $partitionPath = if ($expectedUnit -ceq 'main') {
            "$base.c"
        } else {
            "$base" + '_' + $expectedUnit.Substring(5) + '.c'
        }
        Assert-ProvenanceCondition `
            -Condition (
                [string] $record.path -ceq $partitionPath -and
                $partitionPaths.Add($partitionPath) -and
                (Test-ProvenanceHash -Value $record.sha256)
            ) `
            -Code 'partition-path'
        $partitionFull = Resolve-ProvenanceSourcePath `
            -SourceRoot $Source `
            -RelativePath $partitionPath
        Assert-ProvenanceCondition `
            -Condition (
                (Get-ProvenanceSha256 -Path $partitionFull) -ceq
                    [string] $record.sha256 -and
                [uint64] $record.functions -eq
                    [uint64] $reportPartition.functions -and
                [uint64] $record.instructions -eq
                    [uint64] $reportPartition.instructions -and
                [string] $record.firstKey -ceq
                    [string] $reportPartition.firstKey -and
                [string] $record.lastKey -ceq
                    [string] $reportPartition.lastKey
            ) `
            -Code 'partition-drift'
        if ($expectedUnit -cne 'main') {
            $GeneratedExpected.Add(
                $partitionPath,
                [pscustomobject]@{
                    Kind = 'module-partition'
                    ModuleId = [string] $Module.id
                }
            )
        }
    }
    $GeneratedExpected.Add(
        "$base.h",
        [pscustomobject]@{
            Kind = 'module-header'
            ModuleId = [string] $Module.id
        }
    )

    return [pscustomobject]@{
        Id = [string] $Module.id
        Base = $base
        Sidecar = $sidecar
        Report = $report
        NamedTraps = $namedTrapCount
    }
}

try {
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $SourceRoot -PathType Container) `
        -Code 'source-root'
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $RuntimeManifest -PathType Leaf) `
        -Code 'runtime-manifest'
    $source = [IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $SourceRoot).ProviderPath
    ).TrimEnd('\')
    $repository = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $document = Read-ProvenanceJson `
        -Path $ProvenanceFile `
        -Code 'provenance-json'

    Test-ProvenanceExactProperties `
        -Value $document `
        -Names @(
            'schemaVersion',
            'entryPolicyVersion',
            'framework',
            'generator',
            'runtimeManifest',
            'entryModuleId',
            'modules',
            'aggregate',
            'generatedFiles'
        ) `
        -Code 'provenance-schema'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger -Value $document.schemaVersion) -and
            (Test-ProvenanceInteger `
                -Value $document.entryPolicyVersion) -and
            [uint64] $document.schemaVersion -eq 2 -and
            [uint64] $document.entryPolicyVersion -eq 1 -and
            $document.modules -is [Array] -and
            $document.generatedFiles -is [Array]
        ) `
        -Code 'provenance-version'
    Test-ProvenanceExactProperties `
        -Value $document.framework `
        -Names @('commit') `
        -Code 'framework-shape'
    Assert-ProvenanceCondition `
        -Condition (
            $document.framework.commit -is [string] -and
            ([string] $document.framework.commit) -cmatch '^[0-9a-f]{40}$'
        ) `
        -Code 'framework-commit'
    $pinPath = Join-Path $repository 'config\framework.commit'
    Assert-ProvenanceCondition `
        -Condition (Test-Path -LiteralPath $pinPath -PathType Leaf) `
        -Code 'framework-pin'
    $pin = ([IO.File]::ReadAllText($pinPath)).Trim()
    Assert-ProvenanceCondition `
        -Condition (
            $pin -cmatch '^[0-9a-f]{40}$' -and
            $pin -ceq [string] $document.framework.commit
        ) `
        -Code 'framework-revision-mismatch'

    Test-ProvenanceExactProperties `
        -Value $document.generator `
        -Names @(
            'name',
            'executableSha256',
            'moduleSidecarSchemaVersion',
            'moduleReportSchemaVersion',
            'composeReportSchemaVersion',
            'commands',
            'environment'
        ) `
        -Code 'generator-shape'
    Assert-ProvenanceCondition `
        -Condition (
            $document.generator.name -ceq 'armrecomp' -and
            (Test-ProvenanceHash `
                -Value $document.generator.executableSha256) -and
            (Test-ProvenanceInteger `
                -Value $document.generator.moduleSidecarSchemaVersion) -and
            (Test-ProvenanceInteger `
                -Value $document.generator.moduleReportSchemaVersion) -and
            (Test-ProvenanceInteger `
                -Value $document.generator.composeReportSchemaVersion) -and
            [uint64] $document.generator.moduleSidecarSchemaVersion -eq 4 -and
            [uint64] $document.generator.moduleReportSchemaVersion -eq 4 -and
            [uint64] $document.generator.composeReportSchemaVersion -eq 4 -and
            $document.generator.commands -is [Array] -and
            $document.generator.environment -is [Array]
        ) `
        -Code 'generator-identity'
    if (-not [string]::IsNullOrWhiteSpace($GeneratorExecutable)) {
        Assert-ProvenanceCondition `
            -Condition (
                (Get-ProvenanceSha256 -Path $GeneratorExecutable) -ceq
                    [string] $document.generator.executableSha256
            ) `
            -Code 'generator-mismatch'
    }

    Test-ProvenanceExactProperties `
        -Value $document.runtimeManifest `
        -Names @('sha256') `
        -Code 'runtime-manifest-shape'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceHash `
                -Value $document.runtimeManifest.sha256) -and
            (Get-ProvenanceSha256 -Path $RuntimeManifest) -ceq
                [string] $document.runtimeManifest.sha256
        ) `
        -Code 'runtime-manifest-mismatch'
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceModuleId -Value $document.entryModuleId) `
        -Code 'entry-module-id'

    $generatedExpected = New-Object (
        'System.Collections.Generic.Dictionary[string, object]'
    ) ([StringComparer]::Ordinal)
    $modules = @($document.modules)
    Assert-ProvenanceCondition `
        -Condition ($modules.Count -ge 1 -and $modules.Count -le 64) `
        -Code 'module-count'
    Test-ProvenanceSortedUnique `
        -Items $modules `
        -Selector { param($item) $item.id } `
        -Code 'module-order-or-collision'
    $evidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($module in $modules) {
        $evidence.Add((
            Test-ModuleEvidence `
                -Module $module `
                -Source $source `
                -GeneratedExpected $generatedExpected
        ))
    }
    $entryModules = @(
        $modules | Where-Object {
            [string] $_.id -ceq [string] $document.entryModuleId
        }
    )
    Assert-ProvenanceCondition `
        -Condition ($entryModules.Count -eq 1) `
        -Code 'entry-module-mismatch'

    $commands = @($document.generator.commands)
    Assert-ProvenanceCondition `
        -Condition ($commands.Count -eq $modules.Count + 1) `
        -Code 'command-count'
    $emitIds = New-Object 'System.Collections.Generic.List[string]'
    $commonExecutable = $null
    for ($index = 0; $index -lt $commands.Count; $index++) {
        $command = $commands[$index]
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
        Assert-ProvenanceCondition `
            -Condition (
                (Test-ProvenanceInteger -Value $command.sequence) -and
                [uint64] $command.sequence -eq [uint64] $index -and
                ($command.phase -ceq 'emit' -or
                    $command.phase -ceq 'compose') -and
                (Test-ProvenanceCommandToken -Value $command.executable) -and
                ([string] $command.executable) -cmatch
                    '^(?:[A-Za-z0-9._+-]+/)*armrecomp(?:\.exe)?$' -and
                $command.arguments -is [Array]
            ) `
            -Code 'command-normalization'
        if ($null -eq $commonExecutable) {
            $commonExecutable = [string] $command.executable
        } else {
            Assert-ProvenanceCondition `
                -Condition (
                    [string] $command.executable -ceq $commonExecutable
                ) `
                -Code 'command-generator-drift'
        }
        $arguments = @($command.arguments)
        Assert-ProvenanceCondition `
            -Condition ($arguments.Count -gt 0) `
            -Code 'command-arguments'
        foreach ($argument in $arguments) {
            Assert-ProvenanceCondition `
                -Condition (Test-ProvenanceCommandToken -Value $argument) `
                -Code 'command-absolute-or-unsafe'
        }
        if ($index -lt $modules.Count) {
            Assert-ProvenanceCondition `
                -Condition (
                    $command.phase -ceq 'emit' -and
                    (Test-ProvenanceModuleId -Value $command.moduleId) -and
                    [string] $command.moduleId -ceq
                        [string] $modules[$index].id -and
                    [string] $arguments[0] -ceq 'emit'
                ) `
                -Code 'emit-command-order'
            $moduleOption = [Array]::IndexOf(
                [object[]] $arguments,
                [object] '--module-id'
            )
            Assert-ProvenanceCondition `
                -Condition (
                    $moduleOption -ge 0 -and
                    $moduleOption + 1 -lt $arguments.Count -and
                    [string] $arguments[$moduleOption + 1] -ceq
                        [string] $command.moduleId -and
                    $arguments -ccontains (
                        [string] $evidence[$index].Base + '.c'
                    )
                ) `
                -Code 'emit-command-drift'
            $emitIds.Add([string] $command.moduleId)
        } else {
            Assert-ProvenanceCondition `
                -Condition (
                    $command.phase -ceq 'compose' -and
                    $null -eq $command.moduleId -and
                    [string] $arguments[0] -ceq 'compose'
                ) `
                -Code 'compose-command-position'
        }
    }

    $environment = @($document.generator.environment)
    $expectedKnobs = @(
        'VITARECOMP_EMIT_PC',
        'VITARECOMP_EMIT_SPLIT',
        'VITARECOMP_EMIT_SPLIT_INSNS',
        'VITARECOMP_WHY'
    )
    Assert-ProvenanceCondition `
        -Condition ($environment.Count -eq $expectedKnobs.Count) `
        -Code 'environment-count'
    for ($index = 0; $index -lt $expectedKnobs.Count; $index++) {
        $knob = $environment[$index]
        Test-ProvenanceExactProperties `
            -Value $knob `
            -Names @('name', 'value') `
            -Code 'environment-shape'
        Assert-ProvenanceCondition `
            -Condition (
                [string] $knob.name -ceq $expectedKnobs[$index] -and
                ($null -eq $knob.value -or
                    ($knob.value -is [string] -and
                        ([string] $knob.value) -cmatch '^[ -~]*$'))
            ) `
            -Code 'environment-normalization'
    }
    $pcValue = $environment[0].value
    Assert-ProvenanceCondition `
        -Condition (
            $pcValue -is [string] -and
            -not [string]::IsNullOrWhiteSpace([string] $pcValue) -and
            [string] $pcValue -cne '0'
        ) `
        -Code 'missing-pc-environment'

    Test-ProvenanceExactProperties `
        -Value $document.aggregate `
        -Names @(
            'reportJson',
            'reportText',
            'registrySource',
            'registryHeader',
            'moduleCount',
            'tlsLayout',
            'structuralReady',
            'entryEligible',
            'productionReady',
            'pcInstrumentation',
            'entryMatches',
            'classifiedNamedTraps',
            'blockers'
        ) `
        -Code 'aggregate-shape'
    foreach ($value in @(
        $document.aggregate.structuralReady,
        $document.aggregate.entryEligible,
        $document.aggregate.productionReady,
        $document.aggregate.pcInstrumentation
    )) {
        Test-BooleanValue -Value $value -Code 'aggregate-boolean'
    }
    foreach ($value in @(
        $document.aggregate.moduleCount,
        $document.aggregate.entryMatches,
        $document.aggregate.classifiedNamedTraps
    )) {
        Test-IntegerValue `
            -Value $value `
            -Maximum ([uint64]::MaxValue) `
            -Code 'aggregate-count'
    }
    Assert-ProvenanceCondition `
        -Condition ($document.aggregate.blockers -is [Array]) `
        -Code 'aggregate-blockers'
    foreach ($name in @(
        'reportJson',
        'reportText',
        'registrySource',
        'registryHeader'
    )) {
        Test-ProvenanceArtifact `
            -Artifact $document.aggregate.$name `
            -SourceRoot $source `
            -Code 'aggregate-artifact'
    }
    $aggregateReportPath = [string] $document.aggregate.reportJson.path
    Assert-ProvenanceCondition `
        -Condition $aggregateReportPath.EndsWith(
            '.report.json',
            [StringComparison]::Ordinal
        ) `
        -Code 'aggregate-report-name'
    $registryBase = $aggregateReportPath.Substring(
        0,
        $aggregateReportPath.Length - '.report.json'.Length
    )
    Assert-ProvenanceCondition `
        -Condition (
            [string] $document.aggregate.reportText.path -ceq
                "$registryBase.report.txt" -and
            [string] $document.aggregate.registrySource.path -ceq
                "$registryBase.c" -and
            [string] $document.aggregate.registryHeader.path -ceq
                "$registryBase.h"
        ) `
        -Code 'aggregate-artifact-name'
    $generatedExpected.Add(
        "$registryBase.c",
        [pscustomobject]@{
            Kind = 'registry-source'
            ModuleId = $null
        }
    )
    $generatedExpected.Add(
        "$registryBase.h",
        [pscustomobject]@{
            Kind = 'registry-header'
            ModuleId = $null
        }
    )

    $aggregateReport = Read-ProvenanceJson -Path (
        Resolve-ProvenanceSourcePath `
            -SourceRoot $source `
            -RelativePath $document.aggregate.reportJson.path
    ) -Code 'aggregate-report-json'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport `
        -Names @(
            'schemaVersion',
            'generator',
            'entryModuleId',
            'moduleCount',
            'strictUnsupported',
            'structuralReady',
            'entryEligible',
            'productionReady',
            'instrumentation',
            'entry',
            'tlsLayout',
            'totals',
            'modules'
        ) `
        -Code 'aggregate-report-schema'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.instrumentation `
        -Names @('functionEntry', 'pc') `
        -Code 'aggregate-instrumentation'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.entry `
        -Names @(
            'moduleId',
            'rawAddress',
            'dispatchKey',
            'symbol',
            'matches'
        ) `
        -Code 'aggregate-entry'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.tlsLayout `
        -Names @('moduleCount', 'dataSize', 'dataAlignment', 'items') `
        -Code 'aggregate-tls-layout'
    Test-ProvenanceExactProperties `
        -Value $document.aggregate.tlsLayout `
        -Names @('moduleCount', 'dataSize', 'dataAlignment', 'items') `
        -Code 'provenance-tls-layout'
    Assert-ProvenanceCondition `
        -Condition (
            $aggregateReport.tlsLayout.items -is [Array] -and
            $document.aggregate.tlsLayout.items -is [Array]
        ) `
        -Code 'provenance-tls-layout-items'
    Assert-ProvenanceCondition `
        -Condition (
            (ConvertTo-ProvenanceCanonicalJson `
                -Value $document.aggregate.tlsLayout) -ceq
                (ConvertTo-ProvenanceCanonicalJson `
                    -Value $aggregateReport.tlsLayout)
        ) `
        -Code 'provenance-tls-layout-drift'
    Assert-ProvenanceCondition `
        -Condition (
            ([string] $aggregateReport.entry.rawAddress) -cmatch
                '^0x[0-9A-F]{8}$' -and
            ([string] $aggregateReport.entry.dispatchKey) -cmatch
                '^0x[0-9A-F]{8}$'
        ) `
        -Code 'aggregate-entry-address'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals `
        -Names @(
            'ranges',
            'dispatchEntries',
            'functions',
            'instructions',
            'traps',
            'partitions',
            'metadata'
        ) `
        -Code 'aggregate-totals'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.ranges `
        -Names @('load', 'executable') `
        -Code 'aggregate-ranges'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.functions `
        -Names @('emitted', 'discovered', 'dropped', 'promotedWeakRoots') `
        -Code 'aggregate-functions'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.instructions `
        -Names @('total', 'translated', 'trapped', 'bodyCuts') `
        -Code 'aggregate-instructions'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.traps `
        -Names @('total', 'classified', 'unclassified', 'other', 'kinds') `
        -Code 'aggregate-traps'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.partitions `
        -Names @('reported', 'unreported') `
        -Code 'aggregate-partitions'
    Test-ProvenanceExactProperties `
        -Value $aggregateReport.totals.metadata `
        -Names @(
            'tlsModules',
            'functionImports',
            'functionExports',
            'variableExports',
            'tlsVariableExports',
            'variableImports',
            'variableSites'
        ) `
        -Code 'aggregate-metadata'
    Assert-ProvenanceCondition `
        -Condition (
            (Test-ProvenanceInteger `
                -Value $aggregateReport.schemaVersion) -and
            [uint64] $aggregateReport.schemaVersion -eq 4 -and
            $aggregateReport.generator -ceq 'armrecomp-compose' -and
            $aggregateReport.strictUnsupported -eq $true -and
            $aggregateReport.modules -is [Array] -and
            $aggregateReport.totals.traps.kinds -is [Array]
        ) `
        -Code 'aggregate-report-identity'
    foreach ($value in @(
        $aggregateReport.structuralReady,
        $aggregateReport.entryEligible,
        $aggregateReport.productionReady,
        $aggregateReport.instrumentation.functionEntry,
        $aggregateReport.instrumentation.pc
    )) {
        Test-BooleanValue -Value $value -Code 'aggregate-report-boolean'
    }
    Assert-ProvenanceCondition `
        -Condition (
            [uint64] $aggregateReport.totals.instructions.translated +
                [uint64] $aggregateReport.totals.instructions.trapped -eq
                [uint64] $aggregateReport.totals.instructions.total -and
            [uint64] $aggregateReport.totals.instructions.trapped -eq
                [uint64] $aggregateReport.totals.traps.total -and
            [uint64] $aggregateReport.totals.traps.total -eq
                [uint64] $aggregateReport.totals.traps.classified +
                [uint64] $aggregateReport.totals.traps.unclassified -and
            [bool] $aggregateReport.productionReady -eq (
                [uint64] $aggregateReport.totals.traps.total -eq 0 -and
                [uint64] $aggregateReport.totals.instructions.bodyCuts -eq
                    0 -and
                [uint64] $aggregateReport.totals.partitions.unreported -eq 0
            )
        ) `
        -Code 'aggregate-report-arithmetic'
    $aggregateTrapNames = New-Object (
        'System.Collections.Generic.HashSet[string]'
    ) ([StringComparer]::Ordinal)
    [uint64] $aggregateNamedTraps = 0
    [uint64] $aggregatePreviousCount = [uint64]::MaxValue
    $aggregatePreviousName = ''
    foreach ($trap in @($aggregateReport.totals.traps.kinds)) {
        Test-ProvenanceExactProperties `
            -Value $trap `
            -Names @('kind', 'count') `
            -Code 'aggregate-trap-kind-shape'
        Test-IntegerValue `
            -Value $trap.count `
            -Maximum ([uint64]::MaxValue) `
            -Code 'aggregate-trap-count'
        Assert-ProvenanceCondition `
            -Condition (
                $trap.kind -is [string] -and
                -not [string]::IsNullOrWhiteSpace([string] $trap.kind) -and
                ([string] $trap.kind) -cmatch '^[ -~]+$' -and
                [uint64] $trap.count -gt 0 -and
                $aggregateTrapNames.Add([string] $trap.kind) -and
                [uint64] $trap.count -le $aggregatePreviousCount -and
                (
                    [uint64] $trap.count -lt $aggregatePreviousCount -or
                    [StringComparer]::Ordinal.Compare(
                        $aggregatePreviousName,
                        [string] $trap.kind
                    ) -lt 0
                )
            ) `
            -Code 'aggregate-trap-order'
        $aggregatePreviousCount = [uint64] $trap.count
        $aggregatePreviousName = [string] $trap.kind
        $aggregateNamedTraps += [uint64] $trap.count
    }
    Assert-ProvenanceCondition `
        -Condition (
            [uint64] $aggregateReport.totals.traps.other -eq 0 -and
            $aggregateNamedTraps -eq
                [uint64] $aggregateReport.totals.traps.classified
        ) `
        -Code 'aggregate-trap-drift'

    $aggregateModules = @($aggregateReport.modules)
    foreach ($value in @(
        $aggregateReport.tlsLayout.moduleCount,
        $aggregateReport.tlsLayout.dataSize,
        $aggregateReport.tlsLayout.dataAlignment
    )) {
        Test-IntegerValue `
            -Value $value `
            -Maximum ([uint32]::MaxValue) `
            -Code 'aggregate-tls-layout-value'
    }
    $tlsLayoutItems = @($aggregateReport.tlsLayout.items)
    Assert-ProvenanceCondition `
        -Condition (
            [uint64] $aggregateReport.tlsLayout.moduleCount -eq
                [uint64] $tlsLayoutItems.Count -and
            [uint64] $aggregateReport.tlsLayout.moduleCount -eq
                [uint64] $aggregateReport.totals.metadata.tlsModules -and
            [uint64] $aggregateReport.tlsLayout.dataAlignment -ge 16 -and
            (Test-ProvenancePowerOfTwo `
                -Value $aggregateReport.tlsLayout.dataAlignment)
        ) `
        -Code 'aggregate-tls-layout-count'
    [uint64] $expectedTlsDataSize = 0
    [uint64] $expectedTlsDataAlignment = 16
    $tlsModuleIds = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal
    )
    $tlsDescriptorIndices = New-Object (
        'System.Collections.Generic.HashSet[string]'
    ) ([StringComparer]::Ordinal)
    [int64] $previousTlsDescriptorIndex = -1
    for ($tlsIndex = 0; $tlsIndex -lt $tlsLayoutItems.Count; $tlsIndex++) {
        $tlsItem = $tlsLayoutItems[$tlsIndex]
        Test-ProvenanceExactProperties `
            -Value $tlsItem `
            -Names @(
                'moduleId',
                'descriptorIndex',
                'order',
                'offset',
                'alignment'
            ) `
            -Code 'aggregate-tls-layout-item'
        foreach ($value in @(
            $tlsItem.descriptorIndex,
            $tlsItem.order,
            $tlsItem.offset,
            $tlsItem.alignment
        )) {
            Test-IntegerValue `
                -Value $value `
                -Maximum ([uint32]::MaxValue) `
                -Code 'aggregate-tls-layout-item-value'
        }
        Assert-ProvenanceCondition `
            -Condition (
                (Test-ProvenanceModuleId -Value $tlsItem.moduleId) -and
                [uint64] $tlsItem.descriptorIndex -lt
                    [uint64] $aggregateModules.Count -and
                [int64] ([uint64] $tlsItem.descriptorIndex) -gt
                    $previousTlsDescriptorIndex -and
                [uint64] $tlsItem.order -eq [uint64] $tlsIndex -and
                (Test-ProvenancePowerOfTwo -Value $tlsItem.alignment) -and
                $tlsModuleIds.Add([string] $tlsItem.moduleId) -and
                $tlsDescriptorIndices.Add(
                    [string] ([uint64] $tlsItem.descriptorIndex)
                )
            ) `
            -Code 'aggregate-tls-layout-item-value'
        $previousTlsDescriptorIndex =
            [int64] ([uint64] $tlsItem.descriptorIndex)
        $tlsModule = $aggregateModules[
            [int] ([uint64] $tlsItem.descriptorIndex)
        ]
        [uint64] $alignment = [uint64] $tlsItem.alignment
        [uint64] $alignedOffset = $expectedTlsDataSize
        [uint64] $remainder = $alignedOffset % $alignment
        if ($remainder -ne 0) {
            $alignedOffset += $alignment - $remainder
        }
        Assert-ProvenanceCondition `
            -Condition (
                [bool] $tlsModule.tls.present -and
                [string] $tlsItem.moduleId -ceq [string] $tlsModule.id -and
                [uint64] $tlsItem.alignment -eq
                    [uint64] $tlsModule.tls.alignment -and
                [uint64] $tlsItem.order -eq
                    [uint64] $tlsModule.tls.order -and
                [uint64] $tlsItem.offset -eq
                    [uint64] $tlsModule.tls.offset -and
                [uint64] $tlsItem.offset -eq $alignedOffset
            ) `
            -Code 'aggregate-tls-layout-drift'
        $expectedTlsDataSize =
            $alignedOffset + [uint64] $tlsModule.tls.memorySize
        if ($alignment -gt $expectedTlsDataAlignment) {
            $expectedTlsDataAlignment = $alignment
        }
    }
    Assert-ProvenanceCondition `
        -Condition (
            $expectedTlsDataSize -le [uint64] ([uint32]::MaxValue) -and
            [uint64] $aggregateReport.tlsLayout.dataSize -eq
                $expectedTlsDataSize -and
            [uint64] $aggregateReport.tlsLayout.dataAlignment -eq
                $expectedTlsDataAlignment
        ) `
        -Code 'aggregate-tls-layout-size'
    $aggregateIds = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    [uint64] $moduleBodyCuts = 0
    [uint64] $moduleUnreported = 0
    [uint64] $moduleUnclassified = 0
    [uint64] $moduleNamedTraps = 0
    [uint64] $moduleFunctionsEmitted = 0
    [uint64] $moduleFunctionsDiscovered = 0
    [uint64] $moduleFunctionsDropped = 0
    [uint64] $moduleFunctionsPromoted = 0
    [uint64] $moduleInstructionsTotal = 0
    [uint64] $moduleInstructionsTranslated = 0
    [uint64] $moduleInstructionsTrapped = 0
    [uint64] $moduleTrapsTotal = 0
    [uint64] $moduleTrapsOther = 0
    [uint64] $modulePartitionsReported = 0
    [uint64] $moduleLoadRanges = 0
    [uint64] $moduleExecutableRanges = 0
    [uint64] $moduleDispatchEntries = 0
    [uint64] $moduleTlsCount = 0
    [uint64] $moduleFunctionImports = 0
    [uint64] $moduleFunctionExports = 0
    [uint64] $moduleVariableExports = 0
    [uint64] $moduleTlsVariableExports = 0
    [uint64] $moduleVariableImports = 0
    [uint64] $moduleVariableSites = 0
    $moduleStructural = $true
    $modulePc = $true
    $moduleFunctionEntry = $true
    foreach ($item in $aggregateModules) {
        Test-ProvenanceExactProperties `
            -Value $item `
            -Names @(
                'id',
                'name',
                'descriptorSymbol',
                'ranges',
                'dispatchEntries',
                'entry',
                'tls',
                'functionImports',
                'exports',
                'variableImports',
                'report'
            ) `
            -Code 'aggregate-module-shape'
        Assert-ProvenanceCondition `
            -Condition (
                (Test-ProvenanceModuleId -Value $item.id) -and
                $aggregateIds.Add([string] $item.id)
            ) `
            -Code 'aggregate-module-collision'
        $moduleEvidence = @(
            $evidence | Where-Object {
                $_.Id -ceq [string] $item.id
            }
        )
        Assert-ProvenanceCondition `
            -Condition ($moduleEvidence.Count -eq 1) `
            -Code 'aggregate-module-drift'
        Test-ProvenanceExactProperties `
            -Value $item.report `
            -Names @(
                'structuralReady',
                'productionReady',
                'instrumentation',
                'functions',
                'instructions',
                'traps',
                'partitions'
            ) `
            -Code 'aggregate-module-report'
        Test-ProvenanceExactProperties `
            -Value $item.entry `
            -Names @(
                'present',
                'rawAddress',
                'dispatchKey',
                'function',
                'resolved'
            ) `
            -Code 'aggregate-module-entry'
        Test-ProvenanceExactProperties `
            -Value $item.tls `
            -Names @(
                'present',
                'resolved',
                'address',
                'fileSize',
                'memorySize',
                'alignment',
                'order',
                'offset'
            ) `
            -Code 'aggregate-module-tls'
        Test-ProvenanceExactProperties `
            -Value $item.ranges `
            -Names @('load', 'executable') `
            -Code 'aggregate-module-ranges'
        Test-ProvenanceExactProperties `
            -Value $item.functionImports `
            -Names @('count', 'items') `
            -Code 'aggregate-module-function-imports'
        Test-ProvenanceExactProperties `
            -Value $item.exports `
            -Names @('count', 'functions', 'variables', 'tlsVariables', 'items') `
            -Code 'aggregate-module-exports'
        Test-ProvenanceExactProperties `
            -Value $item.variableImports `
            -Names @('count', 'siteCount', 'items') `
            -Code 'aggregate-module-variable-imports'
        Test-ProvenanceExactProperties `
            -Value $item.report.instrumentation `
            -Names @('functionEntry', 'pc') `
            -Code 'aggregate-module-instrumentation'
        Test-ProvenanceExactProperties `
            -Value $item.report.functions `
            -Names @('emitted', 'discovered', 'dropped', 'promotedWeakRoots') `
            -Code 'aggregate-module-functions'
        Test-ProvenanceExactProperties `
            -Value $item.report.instructions `
            -Names @('total', 'translated', 'trapped', 'bodyCuts') `
            -Code 'aggregate-module-instructions'
        Test-ProvenanceExactProperties `
            -Value $item.report.traps `
            -Names @('total', 'classified', 'unclassified', 'other', 'kinds') `
            -Code 'aggregate-module-traps'
        Test-ProvenanceExactProperties `
            -Value $item.report.partitions `
            -Names @('reported', 'unreported') `
            -Code 'aggregate-module-partitions'
        $raw = $moduleEvidence[0].Report
        $rawSidecar = $moduleEvidence[0].Sidecar
        foreach ($value in @(
            $item.tls.present,
            $item.tls.resolved
        )) {
            Test-BooleanValue `
                -Value $value `
                -Code 'aggregate-module-tls-boolean'
        }
        foreach ($value in @(
            $item.tls.fileSize,
            $item.tls.memorySize,
            $item.tls.alignment
        )) {
            Test-IntegerValue `
                -Value $value `
                -Maximum ([uint32]::MaxValue) `
                -Code 'aggregate-module-tls-value'
        }
        if ([bool] $item.tls.present) {
            Test-IntegerValue `
                -Value $item.tls.order `
                -Maximum ([uint32]::MaxValue) `
                -Code 'aggregate-module-tls-order'
            Test-IntegerValue `
                -Value $item.tls.offset `
                -Maximum ([uint32]::MaxValue) `
                -Code 'aggregate-module-tls-offset'
        } else {
            Assert-ProvenanceCondition `
                -Condition (
                    $null -eq $item.tls.order -and
                    $null -eq $item.tls.offset
                ) `
                -Code 'aggregate-module-tls-empty-layout'
        }
        Assert-ProvenanceCondition `
            -Condition (
                $item.report.structuralReady -eq $raw.structuralReady -and
                $item.report.productionReady -eq $raw.productionReady -and
                $item.report.instrumentation.functionEntry -eq
                    $raw.instrumentation.functionEntry -and
                $item.report.instrumentation.pc -eq
                    $raw.instrumentation.pc -and
                [uint64] $item.report.functions.emitted -eq
                    [uint64] $raw.functions.emitted -and
                [uint64] $item.report.functions.discovered -eq
                    [uint64] $raw.functions.discovered -and
                [uint64] $item.report.functions.dropped -eq
                    [uint64] $raw.functions.dropped -and
                [uint64] $item.report.functions.promotedWeakRoots -eq
                    [uint64] $raw.functions.promotedWeakRoots -and
                [uint64] $item.report.instructions.total -eq
                    [uint64] $raw.instructions.total -and
                [uint64] $item.report.instructions.translated -eq
                    [uint64] $raw.instructions.translated -and
                [uint64] $item.report.instructions.trapped -eq
                    [uint64] $raw.instructions.trapped -and
                [uint64] $item.report.instructions.bodyCuts -eq
                    [uint64] $raw.instructions.bodyCuts -and
                [uint64] $item.report.traps.total -eq
                    [uint64] $raw.traps.total -and
                [uint64] $item.report.traps.unclassified -eq
                    [uint64] $raw.traps.unclassified -and
                [uint64] $item.report.traps.classified -eq
                    [uint64] $raw.traps.classified -and
                [uint64] $item.report.traps.other -eq
                    [uint64] $raw.traps.other -and
                [uint64] $item.report.traps.kinds -eq
                    [uint64] (@($raw.traps.kinds).Count) -and
                [uint64] $item.report.partitions.unreported -eq
                    [uint64] $raw.partitions.unreported -and
                [uint64] $item.report.partitions.reported -eq
                    [uint64] (@($raw.partitions.items).Count) -and
                $item.entry.present -eq $rawSidecar.entry.present -and
                $item.entry.resolved -eq $rawSidecar.entry.resolved -and
                [string] $item.entry.rawAddress -ceq
                    [string] $rawSidecar.entry.rawAddress -and
                [string] $item.entry.dispatchKey -ceq
                    [string] $rawSidecar.entry.dispatchKey -and
                [string] $item.entry.function -ceq
                    [string] $rawSidecar.entry.function -and
                $item.tls.present -eq $rawSidecar.tls.present -and
                $item.tls.resolved -eq $rawSidecar.tls.resolved -and
                [string] $item.tls.address -ceq
                    [string] $rawSidecar.tls.address -and
                [uint64] $item.tls.fileSize -eq
                    [uint64] $rawSidecar.tls.fileSize -and
                [uint64] $item.tls.memorySize -eq
                    [uint64] $rawSidecar.tls.memorySize -and
                [uint64] $item.tls.alignment -eq
                    [uint64] $rawSidecar.tls.alignment -and
                [string] $item.name -ceq
                    [string] $rawSidecar.module.name -and
                [string] $item.descriptorSymbol -ceq
                    [string] $rawSidecar.module.descriptorSymbol -and
                [uint64] $item.dispatchEntries -eq
                    [uint64] $rawSidecar.dispatch.count -and
                (ConvertTo-ProvenanceCanonicalJson -Value $item.ranges) -ceq
                    (ConvertTo-ProvenanceCanonicalJson `
                        -Value $rawSidecar.ranges) -and
                (ConvertTo-ProvenanceCanonicalJson `
                    -Value $item.functionImports) -ceq
                    (ConvertTo-ProvenanceCanonicalJson `
                        -Value $rawSidecar.functionImports) -and
                (ConvertTo-ProvenanceCanonicalJson -Value $item.exports) -ceq
                    (ConvertTo-ProvenanceCanonicalJson `
                        -Value $rawSidecar.exports) -and
                [uint64] $item.variableImports.count -eq
                    [uint64] $rawSidecar.variableImports.count -and
                (ConvertTo-ProvenanceCanonicalJson `
                    -Value $item.variableImports.items) -ceq
                    (ConvertTo-ProvenanceCanonicalJson `
                        -Value $rawSidecar.variableImports.items)
            ) `
            -Code 'aggregate-module-report-drift'
        $moduleBodyCuts += [uint64] $raw.instructions.bodyCuts
        $moduleUnreported += [uint64] $raw.partitions.unreported
        $moduleUnclassified += [uint64] $raw.traps.unclassified
        $moduleNamedTraps += [uint64] $moduleEvidence[0].NamedTraps
        $moduleFunctionsEmitted += [uint64] $raw.functions.emitted
        $moduleFunctionsDiscovered += [uint64] $raw.functions.discovered
        $moduleFunctionsDropped += [uint64] $raw.functions.dropped
        $moduleFunctionsPromoted +=
            [uint64] $raw.functions.promotedWeakRoots
        $moduleInstructionsTotal += [uint64] $raw.instructions.total
        $moduleInstructionsTranslated +=
            [uint64] $raw.instructions.translated
        $moduleInstructionsTrapped += [uint64] $raw.instructions.trapped
        $moduleTrapsTotal += [uint64] $raw.traps.total
        $moduleTrapsOther += [uint64] $raw.traps.other
        $modulePartitionsReported +=
            [uint64] (@($raw.partitions.items).Count)
        $moduleLoadRanges += [uint64] (@($rawSidecar.ranges.load).Count)
        $moduleExecutableRanges +=
            [uint64] (@($rawSidecar.ranges.executable).Count)
        $moduleDispatchEntries += [uint64] $rawSidecar.dispatch.count
        if ([bool] $rawSidecar.tls.present) {
            $moduleTlsCount++
        }
        $moduleFunctionImports +=
            [uint64] $rawSidecar.functionImports.count
        $moduleFunctionExports += [uint64] $rawSidecar.exports.functions
        $moduleVariableExports += [uint64] $rawSidecar.exports.variables
        $moduleTlsVariableExports +=
            [uint64] $rawSidecar.exports.tlsVariables
        $moduleVariableImports +=
            [uint64] $rawSidecar.variableImports.count
        foreach ($variableImport in @($rawSidecar.variableImports.items)) {
            $moduleVariableSites +=
                [uint64] (@($variableImport.sites).Count)
        }
        $moduleStructural = $moduleStructural -and
            [bool] $raw.structuralReady
        $modulePc = $modulePc -and [bool] $raw.instrumentation.pc
        $moduleFunctionEntry = $moduleFunctionEntry -and
            [bool] $raw.instrumentation.functionEntry
    }
    Assert-ProvenanceCondition `
        -Condition (
            $aggregateModules.Count -eq $modules.Count -and
            $aggregateReport.moduleCount -eq $modules.Count -and
            $document.aggregate.moduleCount -eq $modules.Count -and
            [uint64] $aggregateReport.totals.ranges.load -eq
                $moduleLoadRanges -and
            [uint64] $aggregateReport.totals.ranges.executable -eq
                $moduleExecutableRanges -and
            [uint64] $aggregateReport.totals.dispatchEntries -eq
                $moduleDispatchEntries -and
            [uint64] $aggregateReport.totals.functions.emitted -eq
                $moduleFunctionsEmitted -and
            [uint64] $aggregateReport.totals.functions.discovered -eq
                $moduleFunctionsDiscovered -and
            [uint64] $aggregateReport.totals.functions.dropped -eq
                $moduleFunctionsDropped -and
            [uint64] $aggregateReport.totals.functions.promotedWeakRoots -eq
                $moduleFunctionsPromoted -and
            [uint64] $aggregateReport.totals.instructions.total -eq
                $moduleInstructionsTotal -and
            [uint64] $aggregateReport.totals.instructions.translated -eq
                $moduleInstructionsTranslated -and
            [uint64] $aggregateReport.totals.instructions.trapped -eq
                $moduleInstructionsTrapped -and
            [uint64] $aggregateReport.totals.instructions.bodyCuts -eq
                $moduleBodyCuts -and
            [uint64] $aggregateReport.totals.traps.total -eq
                $moduleTrapsTotal -and
            [uint64] $aggregateReport.totals.traps.unclassified -eq
                $moduleUnclassified -and
            [uint64] $aggregateReport.totals.traps.classified -eq
                $moduleNamedTraps -and
            [uint64] $aggregateReport.totals.traps.other -eq
                $moduleTrapsOther -and
            [uint64] $aggregateReport.totals.partitions.reported -eq
                $modulePartitionsReported -and
            [uint64] $aggregateReport.totals.partitions.unreported -eq
                $moduleUnreported -and
            [uint64] $aggregateReport.totals.metadata.tlsModules -eq
                $moduleTlsCount -and
            [uint64] $aggregateReport.totals.metadata.functionImports -eq
                $moduleFunctionImports -and
            [uint64] $aggregateReport.totals.metadata.functionExports -eq
                $moduleFunctionExports -and
            [uint64] $aggregateReport.totals.metadata.variableExports -eq
                $moduleVariableExports -and
            [uint64] $aggregateReport.totals.metadata.tlsVariableExports -eq
                $moduleTlsVariableExports -and
            [uint64] $aggregateReport.totals.metadata.variableImports -eq
                $moduleVariableImports -and
            [uint64] $aggregateReport.totals.metadata.variableSites -eq
                $moduleVariableSites
        ) `
        -Code 'aggregate-total-drift'

    $blockers = New-Object 'System.Collections.Generic.List[string]'
    if (-not $moduleStructural -or
        @($modules | Where-Object {
            -not [bool] $_.readiness.structuralReady
        }).Count -gt 0) {
        $blockers.Add('module-not-structurally-ready')
    }
    if (-not [bool] $aggregateReport.structuralReady) {
        $blockers.Add('aggregate-not-structurally-ready')
    }
    if ($moduleBodyCuts -gt 0 -or
        [uint64] $aggregateReport.totals.instructions.bodyCuts -gt 0) {
        $blockers.Add('body-cuts')
    }
    if ($moduleUnreported -gt 0 -or
        [uint64] $aggregateReport.totals.partitions.unreported -gt 0) {
        $blockers.Add('unreported-partitions')
    }
    if ($moduleUnclassified -gt 0 -or
        [uint64] $aggregateReport.totals.traps.unclassified -gt 0) {
        $blockers.Add('unclassified-traps')
    }
    if (-not $modulePc -or
        -not [bool] $aggregateReport.instrumentation.pc) {
        $blockers.Add('missing-pc-instrumentation')
    }
    if (-not $moduleFunctionEntry -or
        -not [bool] $aggregateReport.instrumentation.functionEntry) {
        $blockers.Add('missing-function-entry-instrumentation')
    }
    if (
        [string] $aggregateReport.entryModuleId -cne
            [string] $document.entryModuleId -or
        [string] $aggregateReport.entry.moduleId -cne
            [string] $document.entryModuleId
    ) {
        $blockers.Add('entry-module-mismatch')
    }
    $aggregateEntryModules = @(
        $aggregateModules | Where-Object {
            [string] $_.id -ceq [string] $document.entryModuleId
        }
    )
    Assert-ProvenanceCondition `
        -Condition (
            $aggregateEntryModules.Count -eq 1 -and
            [string] $aggregateReport.entry.rawAddress -ceq
                [string] $aggregateEntryModules[0].entry.rawAddress -and
            [string] $aggregateReport.entry.dispatchKey -ceq
                [string] $aggregateEntryModules[0].entry.dispatchKey
        ) `
        -Code 'aggregate-entry-address-drift'
    if ([uint64] $aggregateReport.entry.matches -ne 1 -or
        -not [bool] $aggregateReport.entryEligible) {
        $blockers.Add('duplicate-or-unresolved-entry')
    }
    if ($aggregateReport.moduleCount -ne $modules.Count) {
        $blockers.Add('module-count-mismatch')
    }
    $sortedBlockers = @(
        Get-ProvenanceSortedStrings -Values $blockers.ToArray()
    )
    $recordedBlockers = @($document.aggregate.blockers)
    Assert-ProvenanceCondition `
        -Condition (
            $recordedBlockers.Count -eq $sortedBlockers.Count -and
            (@(
                for ($index = 0;
                    $index -lt $sortedBlockers.Count;
                    $index++) {
                    [string] $recordedBlockers[$index] -ceq
                        [string] $sortedBlockers[$index]
                }
            ) -notcontains $false)
        ) `
        -Code 'aggregate-blocker-drift'
    Assert-ProvenanceCondition `
        -Condition ($sortedBlockers.Count -eq 0) `
        -Code 'entry-policy-blocked'
    Assert-ProvenanceCondition `
        -Condition (
            $document.aggregate.structuralReady -eq
                $aggregateReport.structuralReady -and
            $document.aggregate.entryEligible -eq
                $aggregateReport.entryEligible -and
            $document.aggregate.productionReady -eq
                $aggregateReport.productionReady -and
            $document.aggregate.pcInstrumentation -eq
                $aggregateReport.instrumentation.pc -and
            [uint64] $document.aggregate.entryMatches -eq
                [uint64] $aggregateReport.entry.matches -and
            [uint64] $document.aggregate.classifiedNamedTraps -eq
                $moduleNamedTraps
        ) `
        -Code 'aggregate-readiness-drift'

    $composeCommand = $commands[$commands.Count - 1]
    $expectedComposeArguments = New-Object 'System.Collections.Generic.List[string]'
    $expectedComposeArguments.Add('compose')
    $expectedComposeArguments.Add('--entry-module')
    $expectedComposeArguments.Add([string] $document.entryModuleId)
    $expectedComposeArguments.Add('--output')
    $expectedComposeArguments.Add(
        [string] $document.aggregate.registrySource.path
    )
    $composeInputs = New-Object 'System.Collections.Generic.List[string]'
    foreach ($module in $modules) {
        $composeInputs.Add([string] $module.reportJson.path)
        $composeInputs.Add([string] $module.sidecar.path)
    }
    foreach ($path in (
        Get-ProvenanceSortedStrings -Values $composeInputs.ToArray()
    )) {
        $expectedComposeArguments.Add($path)
    }
    Assert-ProvenanceCondition `
        -Condition (
            @($composeCommand.arguments).Count -eq
                $expectedComposeArguments.Count -and
            (@(
                for ($index = 0;
                    $index -lt $expectedComposeArguments.Count;
                    $index++) {
                    [string] $composeCommand.arguments[$index] -ceq
                        [string] $expectedComposeArguments[$index]
                }
            ) -notcontains $false)
        ) `
        -Code 'compose-command-drift'

    foreach ($moduleEvidence in $evidence) {
        $importPrefix = [string] $moduleEvidence.Base + '_imports/'
        $importFiles = @(
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
        foreach ($path in (
            Get-ProvenanceSortedStrings -Values $importFiles
        )) {
            if ($generatedExpected.ContainsKey($path)) {
                Stop-ProvenanceValidation -Code 'generated-path-collision'
            }
            $generatedExpected.Add(
                $path,
                [pscustomobject]@{
                    Kind = 'import-source'
                    ModuleId = [string] $moduleEvidence.Id
                }
            )
        }
    }

    $actualGenerated = @(
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
    $actualGenerated = @(
        Get-ProvenanceSortedStrings -Values $actualGenerated
    )
    Assert-ProvenanceCondition `
        -Condition ($actualGenerated.Count -eq $generatedExpected.Count) `
        -Code 'generated-inventory-count'
    foreach ($path in $actualGenerated) {
        Assert-ProvenanceCondition `
            -Condition $generatedExpected.ContainsKey($path) `
            -Code 'unclassified-generated-file'
    }

    $inventory = @($document.generatedFiles)
    Assert-ProvenanceCondition `
        -Condition ($inventory.Count -eq $actualGenerated.Count) `
        -Code 'generated-inventory-count'
    Test-ProvenanceSortedUnique `
        -Items $inventory `
        -Selector { param($item) $item.path } `
        -Code 'generated-inventory-order-or-collision'
    for ($index = 0; $index -lt $inventory.Count; $index++) {
        $record = $inventory[$index]
        Test-ProvenanceExactProperties `
            -Value $record `
            -Names @('path', 'sha256', 'kind', 'moduleId') `
            -Code 'generated-file-shape'
        Assert-ProvenanceCondition `
            -Condition (
                [string] $record.path -ceq $actualGenerated[$index] -and
                (Test-ProvenanceHash -Value $record.sha256) -and
                $generatedExpected.ContainsKey([string] $record.path)
            ) `
            -Code 'generated-file-drift'
        $expected = $generatedExpected[[string] $record.path]
        Assert-ProvenanceCondition `
            -Condition (
                [string] $record.kind -ceq [string] $expected.Kind -and
                (
                    ($null -eq $record.moduleId -and
                        $null -eq $expected.ModuleId) -or
                    ([string] $record.moduleId -ceq
                        [string] $expected.ModuleId)
                ) -and
                (Get-ProvenanceSha256 -Path (
                    Resolve-ProvenanceSourcePath `
                        -SourceRoot $source `
                        -RelativePath $record.path
                )) -ceq [string] $record.sha256
            ) `
            -Code 'generated-file-drift'
    }

    $referencedReports = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal
    )
    foreach ($module in $modules) {
        [void] $referencedReports.Add([string] $module.sidecar.path)
        [void] $referencedReports.Add([string] $module.reportJson.path)
        [void] $referencedReports.Add([string] $module.reportText.path)
    }
    [void] $referencedReports.Add(
        [string] $document.aggregate.reportJson.path
    )
    [void] $referencedReports.Add(
        [string] $document.aggregate.reportText.path
    )
    $actualReports = @(
        Get-ChildItem -LiteralPath $source -File -Recurse -Force |
            ForEach-Object {
                Get-ProvenanceRelativePath `
                    -SourceRoot $source `
                    -Path $_.FullName
            } |
            Where-Object {
                $_.EndsWith(
                    '.module.json',
                    [StringComparison]::Ordinal
                ) -or
                $_.EndsWith(
                    '.report.json',
                    [StringComparison]::Ordinal
                ) -or
                $_.EndsWith(
                    '.report.txt',
                    [StringComparison]::Ordinal
                )
            }
    )
    Assert-ProvenanceCondition `
        -Condition ($actualReports.Count -eq $referencedReports.Count) `
        -Code 'report-inventory-count'
    foreach ($path in $actualReports) {
        Assert-ProvenanceCondition `
            -Condition $referencedReports.Contains($path) `
            -Code 'report-inventory-drift'
    }

    if (-not $Quiet) {
        Write-Host 'Generated-source provenance is valid.'
    }
} catch {
    if ($_.Exception.Message.StartsWith(
        'Generated-source provenance validation failed',
        [StringComparison]::Ordinal
    )) {
        throw
    }
    Stop-ProvenanceValidation -Code 'unexpected-validation-error'
}
