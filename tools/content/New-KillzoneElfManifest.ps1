# SPDX-License-Identifier: GPL-2.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PrivateDataRoot,

    [Parameter(Mandatory = $true)]
    [string] $DumpRoot,

    [Parameter(Mandatory = $true)]
    [string] $ManifestPath,

    [Parameter(Mandatory = $true)]
    [string] $SourceArchivePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string] $SourceArchiveSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{7,40}$')]
    [string] $Vita3KSourceRevision,

    [ValidatePattern('^[A-Z]{4}[0-9]{5}$')]
    [string] $TitleId = 'PCSA00107'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PathWithinRoot {
    param(
        [string] $Candidate,
        [string] $Root
    )

    $fullCandidate = [IO.Path]::GetFullPath($Candidate).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if ($fullCandidate.Equals(
            $fullRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $true
    }

    return $fullCandidate.StartsWith(
        $fullRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-PrivateRoot {
    param([string] $Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Private data root does not exist: '$Root'."
    }

    $rootItem = Get-Item -LiteralPath $Root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Private data root must not be a reparse point.'
    }

    $gitRootOutput = @(
        & git -C $Root rev-parse --show-toplevel 2>$null
    )
    if ($LASTEXITCODE -eq 0 -and $gitRootOutput.Count -gt 0) {
        $gitRoot = [IO.Path]::GetFullPath($gitRootOutput[0])
        if ([IO.Path]::GetFullPath($Root).TrimEnd('\') -eq
            $gitRoot.TrimEnd('\')) {
            throw 'The repository root cannot be used as the private data root.'
        }

        $relative = [IO.Path]::GetFullPath($Root).Substring(
            $gitRoot.TrimEnd('\').Length
        ).TrimStart('\').Replace('\', '/')
        & git -C $gitRoot check-ignore -q -- $relative 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw (
                "Private data root is inside a Git repository but is not ignored: " +
                "'$Root'."
            )
        }
    }
}

function Get-RelativeNormalizedPath {
    param(
        [string] $Path,
        [string] $Root
    )

    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Path is outside dump root: '$fullPath'."
    }
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-OrdinallySortedStrings {
    param([string[]] $Values)

    $result = @($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function Format-Address {
    param([UInt64] $Value)

    return '0x{0:X8}' -f $Value
}

function Get-SegmentFlags {
    param([UInt32] $Flags)

    $read = if (($Flags -band 4) -ne 0) { 'r' } else { '-' }
    $write = if (($Flags -band 2) -ne 0) { 'w' } else { '-' }
    $execute = if (($Flags -band 1) -ne 0) { 'x' } else { '-' }
    return "$read$write$execute"
}

function Read-UInt16LittleEndian {
    param(
        [byte[]] $Bytes,
        [int] $Offset
    )

    return [UInt16] (
        [UInt64] $Bytes[$Offset] +
        ([UInt64] $Bytes[$Offset + 1] * 0x100)
    )
}

function Read-UInt32LittleEndian {
    param(
        [byte[]] $Bytes,
        [int] $Offset
    )

    return [UInt32] (
        [UInt64] $Bytes[$Offset] +
        ([UInt64] $Bytes[$Offset + 1] * 0x100) +
        ([UInt64] $Bytes[$Offset + 2] * 0x10000) +
        ([UInt64] $Bytes[$Offset + 3] * 0x1000000)
    )
}

function Read-Elf32Arm {
    param(
        [string] $Path,
        [string] $RelativePath
    )

    $fileInfo = Get-Item -LiteralPath $Path
    if ($fileInfo.Length -lt 52) {
        throw "ELF '$RelativePath' is shorter than the 52-byte ELF32 header."
    }
    if (($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "ELF '$RelativePath' must not be a reparse point."
    }

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $reader = New-Object IO.BinaryReader($stream)
    try {
        $ident = $reader.ReadBytes(16)
        if (
            $ident.Length -ne 16 -or
            $ident[0] -ne 0x7f -or
            $ident[1] -ne 0x45 -or
            $ident[2] -ne 0x4c -or
            $ident[3] -ne 0x46
        ) {
            throw "ELF '$RelativePath' has invalid ELF magic."
        }
        if ($ident[4] -ne 1) {
            throw "ELF '$RelativePath' is not ELF32."
        }
        if ($ident[5] -ne 1) {
            throw "ELF '$RelativePath' is not little-endian."
        }
        if ($ident[6] -ne 1) {
            throw "ELF '$RelativePath' has an unsupported identification version."
        }

        $type = $reader.ReadUInt16()
        $machine = $reader.ReadUInt16()
        $version = $reader.ReadUInt32()
        $entryPoint = $reader.ReadUInt32()
        $programHeaderOffset = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $headerSize = $reader.ReadUInt16()
        $programHeaderEntrySize = $reader.ReadUInt16()
        $programHeaderCount = $reader.ReadUInt16()
        $null = $reader.ReadUInt16()
        $null = $reader.ReadUInt16()
        $null = $reader.ReadUInt16()

        if ($type -notin @(2, 3, 0xfe00, 0xfe04)) {
            throw (
                "ELF '$RelativePath' has an unsupported executable type " +
                "0x$('{0:X4}' -f $type)."
            )
        }
        if ($machine -ne 40) {
            throw "ELF '$RelativePath' does not target ARM (e_machine=$machine)."
        }
        if ($version -ne 1) {
            throw "ELF '$RelativePath' has an unsupported ELF version."
        }
        if ($headerSize -ne 52) {
            throw "ELF '$RelativePath' has an invalid ELF32 header size."
        }
        if ($programHeaderEntrySize -ne 32) {
            throw "ELF '$RelativePath' has an invalid program-header entry size."
        }
        if ($programHeaderCount -eq 0 -or $programHeaderCount -gt 4096) {
            throw "ELF '$RelativePath' has an invalid program-header count."
        }

        $programTableEnd =
            [UInt64] $programHeaderOffset +
            ([UInt64] $programHeaderEntrySize * $programHeaderCount)
        if ($programTableEnd -gt [UInt64] $fileInfo.Length) {
            throw "ELF '$RelativePath' has a program-header table outside the file."
        }

        $loadSegments = New-Object System.Collections.Generic.List[object]
        $executableSegments = New-Object System.Collections.Generic.List[object]
        for ($index = 0; $index -lt $programHeaderCount; ++$index) {
            $stream.Position =
                [UInt64] $programHeaderOffset +
                ([UInt64] $index * $programHeaderEntrySize)
            $segmentType = $reader.ReadUInt32()
            $fileOffset = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $null = $reader.ReadUInt32()
            $fileSize = $reader.ReadUInt32()
            $memorySize = $reader.ReadUInt32()
            $flags = $reader.ReadUInt32()
            $alignment = $reader.ReadUInt32()

            if ($segmentType -ne 1) {
                continue
            }

            if ($fileSize -gt $memorySize) {
                throw (
                    "ELF '$RelativePath' PT_LOAD[$index] has p_filesz " +
                    'greater than p_memsz.'
                )
            }
            $fileEnd = [UInt64] $fileOffset + [UInt64] $fileSize
            if ($fileEnd -gt [UInt64] $fileInfo.Length) {
                throw (
                    "ELF '$RelativePath' PT_LOAD[$index] extends beyond " +
                    'the file.'
                )
            }
            $memoryEnd = [UInt64] $virtualAddress + [UInt64] $memorySize
            if ($memoryEnd -gt [UInt64] 0x100000000) {
                throw (
                    "ELF '$RelativePath' PT_LOAD[$index] wraps the " +
                    '32-bit address space.'
                )
            }
            if (
                $alignment -gt 1 -and
                (
                    ($alignment -band ($alignment - 1)) -ne 0 -or
                    ($virtualAddress % $alignment) -ne
                        ($fileOffset % $alignment)
                )
            ) {
                throw (
                    "ELF '$RelativePath' PT_LOAD[$index] has invalid " +
                    'alignment.'
                )
            }
            if (($flags -band 1) -ne 0 -and $fileSize -eq 0) {
                throw (
                    "ELF '$RelativePath' PT_LOAD[$index] is executable " +
                    'but has no file bytes.'
                )
            }

            $segment = [pscustomobject]@{
                Index = $index
                FileOffset = [UInt64] $fileOffset
                FileSize = [UInt64] $fileSize
                Start = [UInt64] $virtualAddress
                End = $memoryEnd
                MemorySize = [UInt64] $memorySize
                Flags = [UInt32] $flags
                Alignment = [UInt64] $alignment
            }
            $loadSegments.Add($segment)
            if (($flags -band 1) -ne 0) {
                $executableSegments.Add($segment)
            }
        }

        if ($loadSegments.Count -eq 0) {
            throw "ELF '$RelativePath' has no PT_LOAD segments."
        }
        if ($executableSegments.Count -eq 0) {
            throw "ELF '$RelativePath' has no executable PT_LOAD segment."
        }

        # Vita uses e_entry as a segment selector plus module-info offset,
        # not as an absolute native entry point.
        $moduleInfoSegmentIndex = [int] ($entryPoint -shr 30)
        $moduleInfoOffset = [UInt64] ($entryPoint -band 0x3fffffff)
        $moduleInfoSegment = @(
            $loadSegments |
                Where-Object { $_.Index -eq $moduleInfoSegmentIndex }
        )
        if ($moduleInfoSegment.Count -ne 1) {
            throw (
                "ELF '$RelativePath' module-info selector does not name " +
                'a PT_LOAD program header.'
            )
        }
        $moduleInfoSegment = $moduleInfoSegment[0]
        if (($moduleInfoSegment.Flags -band 1) -eq 0) {
            throw (
                "ELF '$RelativePath' module info is not in an executable " +
                'PT_LOAD segment.'
            )
        }
        if (
            $moduleInfoOffset + 0x5c -gt $moduleInfoSegment.FileSize -or
            $moduleInfoOffset + 0x5c -gt $moduleInfoSegment.MemorySize
        ) {
            throw (
                "ELF '$RelativePath' module info extends outside its " +
                'PT_LOAD segment.'
            )
        }

        $moduleInfoFileOffset =
            $moduleInfoSegment.FileOffset + $moduleInfoOffset
        $stream.Position = $moduleInfoFileOffset
        $moduleInfoBytes = $reader.ReadBytes(0x5c)
        if ($moduleInfoBytes.Length -ne 0x5c) {
            throw "ELF '$RelativePath' has truncated Vita module info."
        }
        $moduleVersion = Read-UInt16LittleEndian $moduleInfoBytes 2
        if (($moduleVersion -shr 8) -ne 1) {
            throw "ELF '$RelativePath' has an unexpected module-info version."
        }

        $moduleNameLength = 0
        while (
            $moduleNameLength -lt 27 -and
            $moduleInfoBytes[4 + $moduleNameLength] -ne 0
        ) {
            $nameByte = $moduleInfoBytes[4 + $moduleNameLength]
            if ($nameByte -lt 0x20 -or $nameByte -gt 0x7e) {
                throw (
                    "ELF '$RelativePath' has a non-printable module name."
                )
            }
            ++$moduleNameLength
        }
        if ($moduleNameLength -eq 0) {
            throw "ELF '$RelativePath' has an empty module name."
        }
        $moduleName = [Text.Encoding]::ASCII.GetString(
            $moduleInfoBytes,
            4,
            $moduleNameLength
        )

        $exportTop = [UInt64] (
            Read-UInt32LittleEndian $moduleInfoBytes 0x24
        )
        $exportEnd = [UInt64] (
            Read-UInt32LittleEndian $moduleInfoBytes 0x28
        )
        $importTop = [UInt64] (
            Read-UInt32LittleEndian $moduleInfoBytes 0x2c
        )
        $importEnd = [UInt64] (
            Read-UInt32LittleEndian $moduleInfoBytes 0x30
        )
        if ($exportTop -gt $exportEnd -or $importTop -gt $importEnd) {
            throw (
                "ELF '$RelativePath' has inverted module import/export bounds."
            )
        }
        if (
            $exportEnd -gt $moduleInfoSegment.MemorySize -or
            $importEnd -gt $moduleInfoSegment.MemorySize
        ) {
            throw (
                "ELF '$RelativePath' module import/export tables extend " +
                'outside the module segment.'
            )
        }
        $moduleInfoVirtualAddress =
            $moduleInfoSegment.Start + $moduleInfoOffset

        $orderedSegments = @(
            $loadSegments |
                Sort-Object -Property Start, FileOffset, Index
        )
        for ($left = 0; $left -lt $orderedSegments.Count; ++$left) {
            if ($orderedSegments[$left].MemorySize -eq 0) {
                continue
            }
            for (
                $right = $left + 1;
                $right -lt $orderedSegments.Count;
                ++$right
            ) {
                if ($orderedSegments[$right].Start -ge
                    $orderedSegments[$left].End) {
                    break
                }
                if ($orderedSegments[$right].MemorySize -gt 0) {
                    throw (
                        "ELF '$RelativePath' has overlapping PT_LOAD ranges."
                    )
                }
            }
        }

        $manifestSegments = New-Object System.Collections.Generic.List[object]
        foreach ($segment in $orderedSegments) {
            $manifestSegments.Add([ordered]@{
                index = $segment.Index
                fileOffset = $segment.FileOffset
                fileSize = $segment.FileSize
                virtualAddress = Format-Address $segment.Start
                memorySize = $segment.MemorySize
                rangeEndExclusive = Format-Address $segment.End
                flags = Get-SegmentFlags $segment.Flags
                alignment = $segment.Alignment
            })
        }

        return [pscustomobject]@{
            EncodedEntry = [UInt64] $entryPoint
            ModuleInfoSegmentIndex = $moduleInfoSegmentIndex
            ModuleInfoSegmentOffset = $moduleInfoOffset
            ModuleInfoVirtualAddress = $moduleInfoVirtualAddress
            ModuleName = $moduleName
            ProgramHeaderCount = $programHeaderCount
            LoadSegments = @($orderedSegments)
            ManifestSegments = $manifestSegments.ToArray()
            FileSize = [UInt64] $fileInfo.Length
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Write-Utf8NoBom {
    param(
        [string] $Path,
        [string] $Content
    )

    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

$privateRoot = [IO.Path]::GetFullPath($PrivateDataRoot)
$dumpDirectory = [IO.Path]::GetFullPath($DumpRoot)
$manifest = [IO.Path]::GetFullPath($ManifestPath)
$sourceArchive = [IO.Path]::GetFullPath($SourceArchivePath)

Assert-PrivateRoot -Root $privateRoot
if (-not (Test-PathWithinRoot -Candidate $dumpDirectory -Root $privateRoot)) {
    throw 'Dump root must be inside the explicit private data root.'
}
if (-not (Test-PathWithinRoot -Candidate $manifest -Root $privateRoot)) {
    throw 'Manifest path must be inside the explicit private data root.'
}
if (-not (Test-Path -LiteralPath $dumpDirectory -PathType Container)) {
    throw "ELF dump root does not exist: '$dumpDirectory'."
}
if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
    throw "Source archive does not exist: '$sourceArchive'."
}

$pathToFile = @{}
$relativePaths = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-ChildItem -LiteralPath $dumpDirectory -File -Recurse) {
    if (-not $file.Extension.Equals(
            '.elf',
            [StringComparison]::OrdinalIgnoreCase
        )) {
        continue
    }
    $relativePath = Get-RelativeNormalizedPath `
        -Path $file.FullName `
        -Root $dumpDirectory
    if ($pathToFile.ContainsKey($relativePath)) {
        throw "Duplicate relative ELF path: '$relativePath'."
    }
    $pathToFile.Add($relativePath, $file.FullName)
    $relativePaths.Add($relativePath)
}

$orderedPaths = Get-OrdinallySortedStrings $relativePaths.ToArray()
if ($orderedPaths.Count -eq 0) {
    throw "No ELF dumps were found below '$dumpDirectory'."
}

$moduleRecords = New-Object System.Collections.Generic.List[object]
$globalRanges = New-Object System.Collections.Generic.List[object]
foreach ($relativePath in $orderedPaths) {
    $fullPath = $pathToFile[$relativePath]
    $elf = Read-Elf32Arm -Path $fullPath -RelativePath $relativePath
    $hash = (
        Get-FileHash -LiteralPath $fullPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    foreach ($segment in $elf.LoadSegments) {
        if ($segment.MemorySize -gt 0) {
            $globalRanges.Add([pscustomobject]@{
                Path = $relativePath
                Index = $segment.Index
                Start = $segment.Start
                End = $segment.End
            })
        }
    }

    $moduleRecords.Add([ordered]@{
        path = $relativePath
        sha256 = $hash
        fileSize = $elf.FileSize
        moduleInfo = [ordered]@{
            name = $elf.ModuleName
            encodedEntry = Format-Address $elf.EncodedEntry
            segmentIndex = $elf.ModuleInfoSegmentIndex
            segmentOffset = $elf.ModuleInfoSegmentOffset
            virtualAddress = Format-Address $elf.ModuleInfoVirtualAddress
        }
        programHeaderCount = $elf.ProgramHeaderCount
        loadSegments = @($elf.ManifestSegments)
    })
}

for ($left = 0; $left -lt $globalRanges.Count; ++$left) {
    for (
        $right = $left + 1;
        $right -lt $globalRanges.Count;
        ++$right
    ) {
        $a = $globalRanges[$left]
        $b = $globalRanges[$right]
        if ($a.Start -lt $b.End -and $b.Start -lt $a.End) {
            throw (
                "Runtime ranges overlap: '$($a.Path)' PT_LOAD[$($a.Index)] " +
                "and '$($b.Path)' PT_LOAD[$($b.Index)]."
            )
        }
    }
}

$manifestObject = [ordered]@{
    schemaVersion = 1
    titleId = $TitleId
    sourceArchive = [ordered]@{
        path = $sourceArchive
        sha256 = $SourceArchiveSha256.ToLowerInvariant()
    }
    vita3k = [ordered]@{
        sourceRevision = $Vita3KSourceRevision.ToLowerInvariant()
        dumpCapability = '--dump-elfs'
    }
    imageFormat = [ordered]@{
        elfClass = 'ELF32'
        byteOrder = 'little-endian'
        machine = 'ARM'
    }
    modules = $moduleRecords.ToArray()
}

$json = $manifestObject | ConvertTo-Json -Depth 16
$json = ($json -replace "`r`n", "`n") + "`n"
Write-Utf8NoBom -Path $manifest -Content $json
Write-Output $manifest
