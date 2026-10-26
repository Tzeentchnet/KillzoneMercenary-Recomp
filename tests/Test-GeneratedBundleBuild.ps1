# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Generator,

    [string] $GeneratorPlatform,

    [string] $GeneratorToolset,

    [string] $Configuration = 'Debug'
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

function ConvertTo-ProcessArgument {
    param([string] $Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + (
        $Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1'
    ) + '"'
}

function Invoke-Tool {
    param(
        [string] $FileName,
        [string[]] $Arguments,
        [hashtable] $Environment = @{}
    )

    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $FileName
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Arguments = (
        @(
            $Arguments |
                ForEach-Object { ConvertTo-ProcessArgument -Value $_ }
        ) -join ' '
    )
    foreach ($entry in $Environment.GetEnumerator()) {
        $start.EnvironmentVariables[$entry.Key] = [string] $entry.Value
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) {
        throw 'Unable to start a generated-bundle test tool.'
    }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(600000)) {
        $process.Kill()
        throw 'A generated-bundle test tool timed out.'
    }
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = (
            $stdout.GetAwaiter().GetResult() +
            $stderr.GetAwaiter().GetResult()
        )
    }
}

function Assert-NoPrivateEvidence {
    param(
        [string] $Output,
        [string[]] $Forbidden
    )

    foreach ($value in $Forbidden) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            foreach ($candidate in @(
                $value,
                $value.Replace('\', '/')
            ) | Select-Object -Unique) {
                Assert-True `
                    -Condition (
                        $Output.IndexOf(
                            $candidate,
                            [StringComparison]::OrdinalIgnoreCase
                        ) -lt 0
                    ) `
                    -Message (
                        'Generated-bundle command output disclosed private ' +
                        'evidence.'
                    )
            }
        }
    }
}

function Assert-ToolResult {
    param(
        [object] $Result,
        [bool] $Success,
        [string] $Label,
        [string[]] $Forbidden
    )

    Assert-NoPrivateEvidence `
        -Output $Result.Output `
        -Forbidden $Forbidden
    if ($Success) {
        Assert-True `
            -Condition ($Result.ExitCode -eq 0) `
            -Message "$Label failed."
    } else {
        Assert-True `
            -Condition ($Result.ExitCode -ne 0) `
            -Message "$Label unexpectedly succeeded."
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

function Set-U16 {
    param(
        [byte[]] $Bytes,
        [int] $Offset,
        [uint16] $Value
    )

    $Bytes[$Offset] = [byte] ($Value -band 0xFF)
    $Bytes[$Offset + 1] = [byte] (($Value -shr 8) -band 0xFF)
}

function Set-U32 {
    param(
        [byte[]] $Bytes,
        [int] $Offset,
        [uint32] $Value
    )

    for ($index = 0; $index -lt 4; $index++) {
        $Bytes[$Offset + $index] = [byte] (
            ($Value -shr ($index * 8)) -band 0xFF
        )
    }
}

function New-SyntheticTitleFixture {
    param([string] $Root)

    $content = Join-Path $Root 'app0'
    $module = Join-Path $content 'module.elf'
    $manifest = Join-Path $Root 'runtime-manifest.json'
    [IO.Directory]::CreateDirectory($content) | Out-Null

    [byte[]] $bytes = New-Object byte[] 512
    $bytes[0] = 0x7F
    $bytes[1] = [byte][char] 'E'
    $bytes[2] = [byte][char] 'L'
    $bytes[3] = [byte][char] 'F'
    $bytes[4] = 1
    $bytes[5] = 1
    $bytes[6] = 1
    Set-U16 -Bytes $bytes -Offset 16 -Value 2
    Set-U16 -Bytes $bytes -Offset 18 -Value 40
    Set-U32 -Bytes $bytes -Offset 20 -Value 1
    Set-U32 -Bytes $bytes -Offset 24 -Value 0x100
    Set-U32 -Bytes $bytes -Offset 28 -Value 52
    Set-U16 -Bytes $bytes -Offset 40 -Value 52
    Set-U16 -Bytes $bytes -Offset 42 -Value 32
    Set-U16 -Bytes $bytes -Offset 44 -Value 1
    Set-U32 -Bytes $bytes -Offset 52 -Value 1
    Set-U32 -Bytes $bytes -Offset 68 -Value 512
    Set-U32 -Bytes $bytes -Offset 72 -Value 8192
    Set-U32 -Bytes $bytes -Offset 76 -Value 5
    Set-U32 -Bytes $bytes -Offset 80 -Value 4096
    Set-U16 -Bytes $bytes -Offset 0x102 -Value 0x0100
    $name = [Text.Encoding]::ASCII.GetBytes('synthetic_module')
    [Array]::Copy($name, 0, $bytes, 0x104, $name.Length)
    Set-U32 -Bytes $bytes -Offset 0x12C -Value 0x160
    Set-U32 -Bytes $bytes -Offset 0x130 -Value 0x184
    Set-U32 -Bytes $bytes -Offset 0x144 -Value 0x1000
    Set-U16 -Bytes $bytes -Offset 0x160 -Value 0x24
    Set-U16 -Bytes $bytes -Offset 0x166 -Value 1
    Set-U32 -Bytes $bytes -Offset 0x16C -Value 0x11223344
    Set-U32 -Bytes $bytes -Offset 0x174 -Value 0x190
    Set-U32 -Bytes $bytes -Offset 0x178 -Value 0x194
    Set-U32 -Bytes $bytes -Offset 0x190 `
        -Value ([Convert]::ToUInt32('AABBCCDD', 16))
    Set-U32 -Bytes $bytes -Offset 0x194 -Value 0x1101
    [IO.File]::WriteAllBytes($module, $bytes)

    $moduleHash = (
        Get-FileHash -LiteralPath $module -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $document = [ordered]@{
        schemaVersion = 1
        titleId = 'PCSA00107'
        sourceArchive = [ordered]@{
            path = 'synthetic.zip'
            sha256 = ('0' * 64) -join ''
        }
        vita3k = [ordered]@{
            sourceRevision = '0000000'
            dumpCapability = '--dump-elfs'
        }
        imageFormat = [ordered]@{
            elfClass = 'ELF32'
            byteOrder = 'little-endian'
            machine = 'ARM'
        }
        modules = @(
            [ordered]@{
                path = 'module.elf'
                sha256 = $moduleHash
                fileSize = 512
                moduleInfo = [ordered]@{
                    name = 'synthetic_module'
                    encodedEntry = '0x00000100'
                    segmentIndex = 0
                    segmentOffset = 256
                    virtualAddress = '0x00000100'
                }
                programHeaderCount = 1
                loadSegments = @(
                    [ordered]@{
                        index = 0
                        fileOffset = 0
                        fileSize = 512
                        virtualAddress = '0x00000000'
                        memorySize = 8192
                        rangeEndExclusive = '0x00002000'
                        flags = 'r-x'
                        alignment = 4096
                    }
                )
            }
        )
    }
    Set-TestContent `
        -Path $manifest `
        -Value (($document | ConvertTo-Json -Depth 16) + "`n")
    return [pscustomobject]@{
        Content = $content
        Manifest = $manifest
        Module = $module
        ModuleHash = $moduleHash
    }
}

function ConvertTo-DeterministicLog {
    param([string] $Output)

    $records = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $record = $line | ConvertFrom-Json
        } catch {
            continue
        }
        $ordered = [ordered]@{}
        foreach ($property in $record.PSObject.Properties) {
            if ($property.Name -cne 'timestamp') {
                $ordered[$property.Name] = $property.Value
            }
        }
        $records.Add(($ordered | ConvertTo-Json -Compress -Depth 8))
    }
    return $records.ToArray() -join "`n"
}

function Copy-StagedBundle {
    param(
        [string] $Source,
        [string] $Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item `
        -LiteralPath $Source `
        -Destination $Destination `
        -Recurse `
        -Force
}

function New-ConfigureArguments {
    param(
        [string] $Repository,
        [string] $Build,
        [string] $Staged,
        [string] $Runtime
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($argument in @(
        '-S',
        $Repository,
        '-B',
        $Build,
        '-G',
        $Generator
    )) {
        $arguments.Add($argument)
    }
    if (-not [string]::IsNullOrWhiteSpace($GeneratorPlatform)) {
        $arguments.Add('-A')
        $arguments.Add($GeneratorPlatform)
    }
    if (-not [string]::IsNullOrWhiteSpace($GeneratorToolset)) {
        $arguments.Add('-T')
        $arguments.Add($GeneratorToolset)
    }
    foreach ($argument in @(
        '-DBUILD_TESTING=ON',
        '-DKZMRECOMP_BUILD_HOST=OFF',
        "-DKZMRECOMP_GENERATED_SOURCE_DIR:PATH=$Staged",
        "-DKZMRECOMP_RUNTIME_MANIFEST:FILEPATH=$Runtime"
    )) {
        $arguments.Add($argument)
    }
    return $arguments.ToArray()
}

function Invoke-ConfigureCase {
    param(
        [string] $Label,
        [string] $Build,
        [string] $Staged,
        [string] $Runtime,
        [bool] $Success,
        [string[]] $Forbidden
    )

    $arguments = New-ConfigureArguments `
        -Repository $repositoryRoot `
        -Build $Build `
        -Staged $Staged `
        -Runtime $Runtime
    $result = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $arguments
    Assert-ToolResult `
        -Result $result `
        -Success $Success `
        -Label $Label `
        -Forbidden @($Forbidden + @($Staged, $Runtime))
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cmake = Get-Command cmake -ErrorAction Stop
$ctest = Get-Command ctest -ErrorAction Stop
$workRoot = Join-Path $repositoryRoot (
    'out\tests\generated-bundle-build-' +
    $PID +
    '-' +
    [Guid]::NewGuid().ToString('N')
)
$bundleRoot = Join-Path $workRoot 'bundle'
$staged = Join-Path $bundleRoot 'staged'
$runtimeManifest = Join-Path (
    $bundleRoot
) 'generator\runtime-manifest.json'
$provenance = Join-Path $staged '.generated-source-provenance.json'

try {
    $titleFixture = New-SyntheticTitleFixture `
        -Root (Join-Path $workRoot 'title-fixture')
    $fixtureOutput = (
        & (Join-Path $PSScriptRoot 'Test-GeneratedSourceProvenance.ps1') `
            -ExportBundleRoot $bundleRoot `
            -ExportRuntimeManifest $titleFixture.Manifest 6>&1 |
            Out-String
    )
    Assert-True `
        -Condition (
            (Test-Path -LiteralPath $provenance -PathType Leaf) -and
            (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)
        ) `
        -Message 'Synthetic generated bundle creation failed.'

    $runtimeHash = (
        Get-FileHash -LiteralPath $runtimeManifest -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $provenanceHash = (
        Get-FileHash -LiteralPath $provenance -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $forbidden = @(
        $staged,
        $runtimeManifest,
        $runtimeHash,
        $provenanceHash,
        $titleFixture.Content,
        $titleFixture.Manifest,
        $titleFixture.ModuleHash
    )
    Assert-NoPrivateEvidence `
        -Output $fixtureOutput `
        -Forbidden $forbidden

    $validBuild = Join-Path $workRoot 'valid-build'
    Invoke-ConfigureCase `
        -Label 'Valid generated-bundle configure' `
        -Build $validBuild `
        -Staged $staged `
        -Runtime $runtimeManifest `
        -Success $true `
        -Forbidden $forbidden

    $buildArguments = @(
        '--build',
        $validBuild,
        '--config',
        $Configuration,
        '--target',
        'kzmrecomp_generated_bundle_tests',
        'kzmrecomp_title_test_driver',
        '--parallel'
    )
    $build = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $build `
        -Success $true `
        -Label 'Valid generated-bundle build' `
        -Forbidden $forbidden
    $adapterExecutables = @(
        Get-ChildItem `
            -LiteralPath $validBuild `
            -Filter 'kzmrecomp_generated_bundle_tests.exe' `
            -File `
            -Recurse
    )
    Assert-True `
        -Condition ($adapterExecutables.Count -eq 1) `
        -Message 'Generated-bundle adapter test executable is unavailable.'
    $adapterImage = [Text.Encoding]::ASCII.GetString(
        [IO.File]::ReadAllBytes($adapterExecutables[0].FullName)
    )
    Assert-True `
        -Condition (
            -not $adapterImage.Contains(
                'synthetic import default selected unexpectedly'
            )
        ) `
        -Message (
            'Generated import defaults linked before the framework HLE ' +
            'implementation.'
        )

    $test = Invoke-Tool `
        -FileName $ctest.Source `
        -Arguments @(
            '--test-dir',
            $validBuild,
            '-C',
            $Configuration,
            '-R',
            '^generated-bundle-adapter-unit$',
            '--output-on-failure',
            '--no-tests=error'
        )
    Assert-ToolResult `
        -Result $test `
        -Success $true `
        -Label 'Generated-bundle adapter presence test' `
        -Forbidden $forbidden

    $titleDrivers = @(
        Get-ChildItem `
            -LiteralPath $validBuild `
            -Filter 'kzmrecomp_title_test_driver.exe' `
            -File `
            -Recurse
    )
    Assert-True `
        -Condition ($titleDrivers.Count -eq 1) `
        -Message 'Synthetic title test driver is unavailable.'
    $firstTitleRun = Invoke-Tool `
        -FileName $titleDrivers[0].FullName `
        -Arguments @($titleFixture.Content, $titleFixture.Manifest)
    Assert-ToolResult `
        -Result $firstTitleRun `
        -Success $true `
        -Label 'Synthetic title completion run' `
        -Forbidden $forbidden
    Assert-True `
        -Condition (
            $firstTitleRun.Output -match '"event":"title_entry_completed"' -and
            $firstTitleRun.Output -match '"entry_calls":"1"' -and
            $firstTitleRun.Output -notmatch '"event":"title_strict_failure"'
        ) `
        -Message 'Synthetic title entry did not complete exactly once.'

    $strictTitleRun = Invoke-Tool `
        -FileName $titleDrivers[0].FullName `
        -Arguments @($titleFixture.Content, $titleFixture.Manifest) `
        -Environment @{
            KZMRECOMP_SYNTHETIC_ENTRY_STRICT = '1'
        }
    Assert-NoPrivateEvidence `
        -Output $strictTitleRun.Output `
        -Forbidden $forbidden
    Assert-True `
        -Condition (
            $strictTitleRun.ExitCode -eq 12 -and
            $strictTitleRun.Output -match '"event":"title_strict_failure"' -and
            $strictTitleRun.Output -match '"source_address":"4096"' -and
            $strictTitleRun.Output -match (
                '"name":"synthetic named strict failure"'
            ) -and
            $strictTitleRun.Output -match '"entry_calls":"1"' -and
            $strictTitleRun.Output -notmatch '"event":"title_entry_completed"'
        ) `
        -Message (
           'Synthetic named strict failure did not stop at one entry call.'
        )

    $secondTitleRun = Invoke-Tool `
        -FileName $titleDrivers[0].FullName `
        -Arguments @($titleFixture.Content, $titleFixture.Manifest)
    Assert-ToolResult `
        -Result $secondTitleRun `
        -Success $true `
        -Label 'Repeated synthetic title completion run' `
        -Forbidden $forbidden
    Assert-True `
        -Condition (
            (ConvertTo-DeterministicLog -Output $firstTitleRun.Output) -ceq
            (ConvertTo-DeterministicLog -Output $secondTitleRun.Output)
        ) `
        -Message 'Repeated synthetic title process runs were not deterministic.'

    foreach ($stage in @(
        'content_identity',
        'memory_layout',
        'runtime_initialization',
        'content_mount',
        'module_preflight',
        'module_load',
        'descriptor_agreement',
        'binding',
        'stack',
        'tls',
        'cpu_state'
    )) {
        $failedStageRun = Invoke-Tool `
            -FileName $titleDrivers[0].FullName `
            -Arguments @(
                $titleFixture.Content,
                $titleFixture.Manifest,
                $stage
            )
        Assert-NoPrivateEvidence `
            -Output $failedStageRun.Output `
            -Forbidden $forbidden
        Assert-True `
            -Condition (
                $failedStageRun.ExitCode -eq 11 -and
                $failedStageRun.Output -match (
                    '"event":"title_precondition_failed"'
                ) -and
                $failedStageRun.Output -match (
                    '"stage":"' + $stage + '"'
                ) -and
                $failedStageRun.Output -match '"entry_calls":"0"' -and
                $failedStageRun.Output -notmatch (
                    '"event":"title_entry_completed"'
                )
            ) `
            -Message (
                "Failed $stage precondition called or completed title entry."
            )
    }

    $mismatchManifest = Join-Path (
        Split-Path -Parent $titleFixture.Manifest
    ) 'runtime-manifest-mismatch.json'
    $mismatchDocument = Get-Content `
        -LiteralPath $titleFixture.Manifest `
        -Raw |
        ConvertFrom-Json
    $mismatchDocument.sourceArchive.path = 'synthetic-mismatch.zip'
    Set-TestContent `
        -Path $mismatchManifest `
        -Value (($mismatchDocument | ConvertTo-Json -Depth 16) + "`n")
    $mismatchRun = Invoke-Tool `
        -FileName $titleDrivers[0].FullName `
        -Arguments @($titleFixture.Content, $mismatchManifest)
    Assert-NoPrivateEvidence `
        -Output $mismatchRun.Output `
        -Forbidden @($forbidden + @($mismatchManifest))
    Assert-True `
        -Condition (
            $mismatchRun.ExitCode -eq 11 -and
            $mismatchRun.Output -match (
                '"event":"title_precondition_failed"'
            ) -and
            $mismatchRun.Output -match '"entry_calls":"0"' -and
            $mismatchRun.Output -notmatch '"event":"title_entry_completed"'
        ) `
        -Message 'Identity failure called or completed the synthetic entry.'

    Invoke-ConfigureCase `
        -Label 'Tracked-source generated-bundle configure' `
        -Build (Join-Path $workRoot 'tracked-source-build') `
        -Staged (Join-Path $repositoryRoot 'tests') `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $missingProvenance = Join-Path $workRoot 'missing-provenance'
    New-Item `
        -ItemType Directory `
        -Path $missingProvenance `
        -Force |
        Out-Null
    Invoke-ConfigureCase `
        -Label 'Missing-provenance generated-bundle configure' `
        -Build (Join-Path $workRoot 'missing-provenance-build') `
        -Staged $missingProvenance `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $digestMismatch = Join-Path $workRoot 'digest-mismatch'
    Copy-StagedBundle -Source $staged -Destination $digestMismatch
    Add-Content `
        -LiteralPath (
            Join-Path $digestMismatch 'modules\module_main.c'
        ) `
        -Value '/* digest mismatch */'
    Invoke-ConfigureCase `
        -Label 'Digest-mismatched generated-bundle configure' `
        -Build (Join-Path $workRoot 'digest-mismatch-build') `
        -Staged $digestMismatch `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $missingGenerated = Join-Path $workRoot 'missing-generated'
    Copy-StagedBundle -Source $staged -Destination $missingGenerated
    Remove-Item -LiteralPath (
        Join-Path $missingGenerated 'modules\module_main_000.c'
    )
    Invoke-ConfigureCase `
        -Label 'Missing generated file configure' `
        -Build (Join-Path $workRoot 'missing-generated-build') `
        -Staged $missingGenerated `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $extraGenerated = Join-Path $workRoot 'extra-generated'
    Copy-StagedBundle -Source $staged -Destination $extraGenerated
    Set-TestContent `
        -Path (Join-Path $extraGenerated 'modules\unexpected.c') `
        -Value '/* unlisted generated source */'
    Invoke-ConfigureCase `
        -Label 'Extra generated file configure' `
        -Build (Join-Path $workRoot 'extra-generated-build') `
        -Staged $extraGenerated `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $extraManaged = Join-Path $workRoot 'extra-managed'
    Copy-StagedBundle -Source $staged -Destination $extraManaged
    $extraManagedPath = Join-Path $extraManaged 'stale-managed.txt'
    Set-TestContent `
        -Path $extraManagedPath `
        -Value 'synthetic stale managed file'
    $sourceManifestPath = Join-Path (
        $extraManaged
    ) '.generated-source-manifest.json'
    $sourceManifest = Get-Content `
        -LiteralPath $sourceManifestPath `
        -Raw |
        ConvertFrom-Json
    $sourceManifest.files = @(
        @($sourceManifest.files) +
            [pscustomobject][ordered]@{
                path = 'stale-managed.txt'
                sha256 = (
                    Get-FileHash `
                        -LiteralPath $extraManagedPath `
                        -Algorithm SHA256
                ).Hash.ToLowerInvariant()
            } |
            Sort-Object -Property path
    )
    Set-TestContent `
        -Path $sourceManifestPath `
        -Value (
            ($sourceManifest | ConvertTo-Json -Depth 4) +
            [Environment]::NewLine
        )
    Invoke-ConfigureCase `
        -Label 'Extra managed file configure' `
        -Build (Join-Path $workRoot 'extra-managed-build') `
        -Staged $extraManaged `
        -Runtime $runtimeManifest `
        -Success $false `
        -Forbidden $forbidden

    $moduleSource = Join-Path $staged 'modules\module_main.c'
    $moduleBytes = [IO.File]::ReadAllBytes($moduleSource)
    [IO.File]::AppendAllText(
        $moduleSource,
        '/* build-time digest mismatch */',
        (New-Object Text.UTF8Encoding($false))
    )
    $failedBuild = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $failedBuild `
        -Success $false `
        -Label 'Build-time digest mismatch' `
        -Forbidden $forbidden
    [IO.File]::WriteAllBytes($moduleSource, $moduleBytes)

    $unexpectedSource = Join-Path $staged 'modules\unexpected.c'
    Set-TestContent `
        -Path $unexpectedSource `
        -Value '/* build-time extra generated source */'
    $failedBuild = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $failedBuild `
        -Success $false `
        -Label 'Build-time extra generated file' `
        -Forbidden $forbidden
    Remove-Item -LiteralPath $unexpectedSource

    $partition = Join-Path $staged 'modules\module_main_000.c'
    $partitionBytes = [IO.File]::ReadAllBytes($partition)
    Remove-Item -LiteralPath $partition
    $failedBuild = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $failedBuild `
        -Success $false `
        -Label 'Build-time missing generated file' `
        -Forbidden $forbidden
    [IO.File]::WriteAllBytes($partition, $partitionBytes)

    $provenanceBytes = [IO.File]::ReadAllBytes($provenance)
    [IO.File]::AppendAllText(
        $provenance,
        [Environment]::NewLine,
        (New-Object Text.UTF8Encoding($false))
    )
    $failedBuild = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $failedBuild `
        -Success $false `
        -Label 'Build-time stale provenance' `
        -Forbidden $forbidden
    [IO.File]::WriteAllBytes($provenance, $provenanceBytes)

    $restoredBuild = Invoke-Tool `
        -FileName $cmake.Source `
        -Arguments $buildArguments
    Assert-ToolResult `
        -Result $restoredBuild `
        -Success $true `
        -Label 'Restored generated-bundle build' `
        -Forbidden $forbidden

    Write-Host 'Generated-bundle configure/build tests passed.'
} finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
