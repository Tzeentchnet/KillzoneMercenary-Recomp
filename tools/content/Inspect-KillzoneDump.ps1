# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ArchivePath,

    [ValidateSet('Json', 'Text')]
    [string] $OutputFormat = 'Text',

    [string] $OutputPath,

    [switch] $IncludeSha256,

    [switch] $Redact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$titleId = 'PCSA00107'
$titleRoot = "app/$titleId"
$requiredEntryPaths = @(
    "$titleRoot/eboot.bin"
    "$titleRoot/game_data/data_ngp.psarc"
    "$titleRoot/sce_sys/package/work.bin"
    "$titleRoot/sce_sys/param.sfo"
)

function Get-OrdinallySortedStrings {
    param([string[]] $Values)

    $result = @($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function Read-ZipEntryPrefix {
    param(
        [System.IO.Compression.ZipArchiveEntry] $Entry,
        [int] $Count
    )

    $buffer = New-Object byte[] $Count
    $stream = $Entry.Open()
    try {
        $offset = 0
        while ($offset -lt $Count) {
            $read = $stream.Read($buffer, $offset, $Count - $offset)
            if ($read -eq 0) {
                break
            }
            $offset += $read
        }

        if ($offset -eq $Count) {
            return $buffer
        }

        $shortBuffer = New-Object byte[] $offset
        if ($offset -gt 0) {
            [Array]::Copy($buffer, $shortBuffer, $offset)
        }
        return $shortBuffer
    } finally {
        $stream.Dispose()
    }
}

function Test-BytePrefix {
    param(
        [byte[]] $Actual,
        [byte[]] $Expected
    )

    if ($Actual.Count -lt $Expected.Count) {
        return $false
    }

    for ($index = 0; $index -lt $Expected.Count; ++$index) {
        if ($Actual[$index] -ne $Expected[$index]) {
            return $false
        }
    }
    return $true
}

function Get-CodeImageFormat {
    param([byte[]] $Prefix)

    if (Test-BytePrefix $Prefix ([byte[]] @(0x53, 0x43, 0x45, 0x00))) {
        return 'self'
    }
    if (Test-BytePrefix $Prefix ([byte[]] @(0x7f, 0x45, 0x4c, 0x46))) {
        return 'elf'
    }
    return 'protected-or-unknown'
}

function Write-Utf8NoBom {
    param(
        [string] $Path,
        [string] $Content
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($fullPath, $Content, $utf8)
}

$archive = [IO.Path]::GetFullPath($ArchivePath)
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Archive does not exist or is not a file: '$archive'."
}

try {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
} catch {
    throw "System.IO.Compression is unavailable: $($_.Exception.Message)"
}

$errors = New-Object System.Collections.Generic.List[string]
$requiredEntries = New-Object System.Collections.Generic.List[object]
$modulePaths = @()
$moduleFormats = New-Object System.Collections.Generic.List[object]
$fileCount = 0
$directoryCount = 0
$unsafeEntryCount = 0
$ebootFormat = 'missing'
$gameDataFormat = 'missing'
$allModulePayloadsVisible = $false

$fileStream = $null
$zip = $null
try {
    try {
        $fileStream = [IO.File]::Open(
            $archive,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $zip = New-Object IO.Compression.ZipArchive(
            $fileStream,
            [IO.Compression.ZipArchiveMode]::Read,
            $false
        )
    } catch {
        throw "Unable to read ZIP central directory: $($_.Exception.Message)"
    }

    $entryMap =
        [Collections.Generic.Dictionary[
            string,
            System.IO.Compression.ZipArchiveEntry
        ]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $zip.Entries) {
        $originalPath = $entry.FullName
        $normalizedPath = $originalPath.Replace('\', '/')
        $segments = @($normalizedPath.Split('/'))
        $isDirectory = $normalizedPath.EndsWith(
            '/',
            [StringComparison]::Ordinal
        )

        if ($isDirectory) {
            ++$directoryCount
        } else {
            ++$fileCount
        }

        $hasEmptyInteriorSegment =
            $normalizedPath -match '(^|/)/(?!$)'
        $unsafe = (
            [string]::IsNullOrWhiteSpace($normalizedPath) -or
            $originalPath.Contains('\') -or
            $normalizedPath.StartsWith('/', [StringComparison]::Ordinal) -or
            $normalizedPath -match '^[A-Za-z]:' -or
            $segments -contains '..' -or
            $hasEmptyInteriorSegment
        )
        if ($unsafe) {
            ++$unsafeEntryCount
            $errors.Add("Unsafe ZIP entry path: '$normalizedPath'.")
            continue
        }

        if ($entryMap.ContainsKey($normalizedPath)) {
            $errors.Add(
                "Duplicate ZIP entry path (case-insensitive): '$normalizedPath'."
            )
            continue
        }
        $entryMap.Add($normalizedPath, $entry)
    }

    foreach ($requiredPath in $requiredEntryPaths) {
        $present = $entryMap.ContainsKey($requiredPath)
        $length = [UInt64] 0
        if ($present) {
            $length = [UInt64] $entryMap[$requiredPath].Length
            if ($length -eq 0) {
                $errors.Add("Required entry is empty: '$requiredPath'.")
            }
        } else {
            $errors.Add("Required entry is missing: '$requiredPath'.")
        }

        $requiredEntries.Add([ordered]@{
            path = $requiredPath
            present = $present
            length = $length
        })
    }

    $modulePaths = @(
        $entryMap.Keys |
            Where-Object {
                $_ -match (
                    '^app/PCSA00107/sce_module/[^/]+\.suprx$'
                )
            }
    )
    $modulePaths = Get-OrdinallySortedStrings $modulePaths
    if ($modulePaths.Count -eq 0) {
        $errors.Add(
            "No module entries matched '$titleRoot/sce_module/*.suprx'."
        )
    }

    foreach ($modulePath in $modulePaths) {
        $moduleEntry = $entryMap[$modulePath]
        if ($moduleEntry.Length -eq 0) {
            $errors.Add("Module entry is empty: '$modulePath'.")
            $format = 'empty'
        } else {
            $format = Get-CodeImageFormat (
                Read-ZipEntryPrefix -Entry $moduleEntry -Count 4
            )
        }
        $moduleFormats.Add([ordered]@{
            path = $modulePath
            length = [UInt64] $moduleEntry.Length
            payloadFormat = $format
        })
    }

    $titlePrefix = "$titleRoot/"
    $titleEntryCount = @(
        $entryMap.Keys |
            Where-Object {
                $_.StartsWith(
                    $titlePrefix,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    ).Count
    if ($titleEntryCount -eq 0) {
        $errors.Add("Archive does not contain the '$titleRoot' title root.")
    }

    if ($entryMap.ContainsKey("$titleRoot/eboot.bin")) {
        $ebootFormat = Get-CodeImageFormat (
            Read-ZipEntryPrefix `
                -Entry $entryMap["$titleRoot/eboot.bin"] `
                -Count 4
        )
    }

    if ($entryMap.ContainsKey("$titleRoot/game_data/data_ngp.psarc")) {
        $gameDataPrefix = Read-ZipEntryPrefix `
            -Entry $entryMap["$titleRoot/game_data/data_ngp.psarc"] `
            -Count 4
        if (Test-BytePrefix `
                $gameDataPrefix `
                ([Text.Encoding]::ASCII.GetBytes('PSAR'))) {
            $gameDataFormat = 'psarc'
        } else {
            $gameDataFormat = 'protected-or-unknown'
        }
    }

    if ($entryMap.ContainsKey("$titleRoot/sce_sys/param.sfo")) {
        $paramPrefix = Read-ZipEntryPrefix `
            -Entry $entryMap["$titleRoot/sce_sys/param.sfo"] `
            -Count 4
        if (-not (Test-BytePrefix `
                $paramPrefix `
                ([byte[]] @(0x00, 0x50, 0x53, 0x46)))) {
            $errors.Add(
                "The required param.sfo entry does not have the PSF signature."
            )
        }
    }

    $allModulePayloadsVisible = (
        $moduleFormats.Count -gt 0 -and
        @(
            $moduleFormats |
                Where-Object {
                    $_.payloadFormat -notin @('self', 'elf')
                }
        ).Count -eq 0
    )
} finally {
    if ($null -ne $zip) {
        $zip.Dispose()
    }
    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

$payloadSignaturesVisible = (
    $ebootFormat -in @('self', 'elf') -and
    $gameDataFormat -eq 'psarc' -and
    $allModulePayloadsVisible
)

if ($payloadSignaturesVisible) {
    $classificationId = 'retail-nonpdrm-payloads-visible'
    $pfsState = 'payload-signatures-visible'
    $classificationSummary =
        'NoNpDRM retail layout is present; named payload signatures are visible.'
} else {
    $classificationId = 'retail-pfs-nonpdrm'
    $pfsState = 'protected'
    $classificationSummary =
        'NoNpDRM retail layout is present and named payloads retain the outer PFS layer.'
}

$archiveHash = $null
if ($IncludeSha256) {
    $archiveHash = (
        Get-FileHash -LiteralPath $archive -Algorithm SHA256
    ).Hash.ToLowerInvariant()
}

$orderedErrors = Get-OrdinallySortedStrings $errors.ToArray()
$archiveInfo = Get-Item -LiteralPath $archive
$reportedPath = $archive
$reportedHash = $archiveHash
if ($Redact) {
    $reportedPath = '<redacted-archive-path>'
    if ($null -ne $reportedHash) {
        $reportedHash = '<redacted>'
    }
}

$report = [ordered]@{
    schemaVersion = 1
    titleId = $titleId
    valid = ($orderedErrors.Count -eq 0)
    archive = [ordered]@{
        path = $reportedPath
        length = [UInt64] $archiveInfo.Length
        sha256 = $reportedHash
    }
    inventory = [ordered]@{
        centralDirectoryEntries = $fileCount + $directoryCount
        files = $fileCount
        directories = $directoryCount
        titleEntries = $titleEntryCount
        unsafeEntries = $unsafeEntryCount
    }
    requiredEntries = $requiredEntries.ToArray()
    modules = $moduleFormats.ToArray()
    protection = [ordered]@{
        classification = $classificationId
        retail = $true
        noNpDrmWorkBinPresent = (
            $requiredEntries |
                Where-Object {
                    $_.path -eq "$titleRoot/sce_sys/package/work.bin"
                }
        ).present
        pfsState = $pfsState
        ebootPayloadFormat = $ebootFormat
        gameDataPayloadFormat = $gameDataFormat
        modulePayloadSignaturesVisible = $allModulePayloadsVisible
        summary = $classificationSummary
    }
    errors = @($orderedErrors)
}

if ($OutputFormat -eq 'Json') {
    $rendered = $report | ConvertTo-Json -Depth 12
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Killzone content archive inspection')
    $lines.Add("Title ID: $titleId")
    $lines.Add("Archive: $reportedPath")
    $lines.Add("Archive bytes: $($archiveInfo.Length)")
    if ($IncludeSha256) {
        $lines.Add("Archive SHA-256: $reportedHash")
    } else {
        $lines.Add('Archive SHA-256: not requested')
    }
    $lines.Add(
        "Central-directory entries: $($fileCount + $directoryCount) " +
        "($fileCount files, $directoryCount directories)"
    )
    foreach ($required in $requiredEntries) {
        $status = if ($required.present -and $required.length -gt 0) {
            'ok'
        } else {
            'missing-or-empty'
        }
        $lines.Add(
            "Required [$status]: $($required.path) ($($required.length) bytes)"
        )
    }
    $lines.Add("Modules: $($moduleFormats.Count)")
    $lines.Add("Protection: $classificationId ($pfsState)")
    $lines.Add("Protection detail: $classificationSummary")
    if ($orderedErrors.Count -gt 0) {
        foreach ($validationError in $orderedErrors) {
            $lines.Add("Error: $validationError")
        }
    }
    $result = if ($orderedErrors.Count -eq 0) { 'VALID' } else { 'INVALID' }
    $lines.Add("Result: $result")
    $rendered = $lines -join "`n"
}

$rendered = ($rendered -replace "`r`n", "`n") + "`n"
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Utf8NoBom -Path $OutputPath -Content $rendered
} else {
    Write-Output $rendered.TrimEnd("`r", "`n")
}

if ($orderedErrors.Count -gt 0) {
    throw "Archive inspection failed with $($orderedErrors.Count) validation error(s)."
}
