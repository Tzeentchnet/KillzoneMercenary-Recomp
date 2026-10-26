# SPDX-License-Identifier: GPL-2.0-or-later

Set-StrictMode -Version Latest

function Stop-ProvenanceValidation {
    param([string] $Code)

    throw "Generated-source provenance validation failed ($Code)."
}

function Assert-ProvenanceCondition {
    param(
        [bool] $Condition,
        [string] $Code
    )

    if (-not $Condition) {
        Stop-ProvenanceValidation -Code $Code
    }
}

function Get-ProvenanceSha256 {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-ProvenanceValidation -Code 'missing-file'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ProvenanceHash {
    param([object] $Value)

    return $Value -is [string] -and
        ([string] $Value) -cmatch '^[0-9a-f]{64}$'
}

function Test-ProvenanceModuleId {
    param([object] $Value)

    return $Value -is [string] -and
        ([string] $Value) -cmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$'
}

function Test-ProvenanceRelativePath {
    param([object] $Value)

    if (-not ($Value -is [string])) {
        return $false
    }
    $path = [string] $Value
    if (
        [string]::IsNullOrWhiteSpace($path) -or
        $path -cne $path.Trim() -or
        $path.Length -gt 1024 -or
        $path.Contains('\') -or
        $path.StartsWith('/', [StringComparison]::Ordinal) -or
        $path.Contains('//') -or
        $path.Contains(':') -or
        $path -cnotmatch '^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$'
    ) {
        return $false
    }
    foreach ($part in $path.Split('/')) {
        if ($part -ceq '.' -or $part -ceq '..') {
            return $false
        }
    }
    return $true
}

function Resolve-ProvenanceSourcePath {
    param(
        [string] $SourceRoot,
        [object] $RelativePath
    )

    if (-not (Test-ProvenanceRelativePath -Value $RelativePath)) {
        Stop-ProvenanceValidation -Code 'unsafe-relative-path'
    }
    $candidate = [IO.Path]::GetFullPath(
        (Join-Path $SourceRoot ([string] $RelativePath).Replace('/', '\'))
    )
    $prefix = $SourceRoot.TrimEnd('\') + '\'
    if (-not $candidate.StartsWith(
        $prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        Stop-ProvenanceValidation -Code 'path-escape'
    }
    return $candidate
}

function Get-ProvenanceRelativePath {
    param(
        [string] $SourceRoot,
        [string] $Path
    )

    $root = $SourceRoot.TrimEnd('\') + '\'
    $rootUri = New-Object Uri($root)
    $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
    $relative = [Uri]::UnescapeDataString(
        $rootUri.MakeRelativeUri($pathUri).ToString()
    ).Replace('\', '/')
    if (-not (Test-ProvenanceRelativePath -Value $relative)) {
        Stop-ProvenanceValidation -Code 'unsafe-discovered-path'
    }
    return $relative
}

function Get-ProvenanceSortedStrings {
    param([string[]] $Values)

    $copy = [string[]] @($Values)
    [Array]::Sort($copy, [StringComparer]::Ordinal)
    return $copy
}

function Test-ProvenanceSortedUnique {
    param(
        [object[]] $Items,
        [scriptblock] $Selector,
        [string] $Code
    )

    $previous = $null
    $caseFolded = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $value = [string] (& $Selector $Items[$index])
        if (
            -not $caseFolded.Add($value) -or
            ($index -gt 0 -and
                [StringComparer]::Ordinal.Compare($previous, $value) -ge 0)
        ) {
            Stop-ProvenanceValidation -Code $Code
        }
        $previous = $value
    }
}

function Test-ProvenanceExactProperties {
    param(
        [object] $Value,
        [string[]] $Names,
        [string] $Code
    )

    if ($null -eq $Value) {
        Stop-ProvenanceValidation -Code $Code
    }
    $actual = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $Names.Count) {
        Stop-ProvenanceValidation -Code $Code
    }
    $expectedSet = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal
    )
    foreach ($name in $Names) {
        [void] $expectedSet.Add($name)
    }
    foreach ($name in $actual) {
        if (-not $expectedSet.Contains([string] $name)) {
            Stop-ProvenanceValidation -Code $Code
        }
    }
}

function Test-ProvenanceInteger {
    param([object] $Value)

    return (
        $Value -is [byte] -or
        $Value -is [int16] -or
        $Value -is [int32] -or
        $Value -is [int64] -or
        $Value -is [uint16] -or
        $Value -is [uint32] -or
        $Value -is [uint64]
    )
}

function Read-ProvenanceJsonStringToken {
    param(
        [string] $Text,
        [ref] $Offset
    )

    if ($Offset.Value -ge $Text.Length -or $Text[$Offset.Value] -cne '"') {
        Stop-ProvenanceValidation -Code 'malformed-json'
    }
    $Offset.Value++
    $builder = New-Object Text.StringBuilder
    while ($Offset.Value -lt $Text.Length) {
        $character = $Text[$Offset.Value]
        $Offset.Value++
        if ($character -ceq '"') {
            return $builder.ToString()
        }
        if ([int] $character -lt 0x20) {
            Stop-ProvenanceValidation -Code 'malformed-json'
        }
        if ($character -cne '\') {
            [void] $builder.Append($character)
            continue
        }
        if ($Offset.Value -ge $Text.Length) {
            Stop-ProvenanceValidation -Code 'malformed-json'
        }
        $escape = $Text[$Offset.Value]
        $Offset.Value++
        switch -CaseSensitive ($escape) {
            '"' { [void] $builder.Append('"') }
            '\' { [void] $builder.Append('\') }
            '/' { [void] $builder.Append('/') }
            'b' { [void] $builder.Append([char] 8) }
            'f' { [void] $builder.Append([char] 12) }
            'n' { [void] $builder.Append([char] 10) }
            'r' { [void] $builder.Append([char] 13) }
            't' { [void] $builder.Append([char] 9) }
            'u' {
                if ($Offset.Value + 4 -gt $Text.Length) {
                    Stop-ProvenanceValidation -Code 'malformed-json'
                }
                $digits = $Text.Substring($Offset.Value, 4)
                if ($digits -cnotmatch '^[0-9A-Fa-f]{4}$') {
                    Stop-ProvenanceValidation -Code 'malformed-json'
                }
                [void] $builder.Append(
                    [char] [Convert]::ToInt32($digits, 16)
                )
                $Offset.Value += 4
            }
            default {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
        }
    }
    Stop-ProvenanceValidation -Code 'malformed-json'
}

function Move-ProvenanceJsonWhitespace {
    param(
        [string] $Text,
        [ref] $Offset
    )

    while (
        $Offset.Value -lt $Text.Length -and
        ($Text[$Offset.Value] -ceq ' ' -or
            $Text[$Offset.Value] -ceq "`t" -or
            $Text[$Offset.Value] -ceq "`r" -or
            $Text[$Offset.Value] -ceq "`n")
    ) {
        $Offset.Value++
    }
}

function Read-ProvenanceJsonValueToken {
    param(
        [string] $Text,
        [ref] $Offset,
        [int] $Depth = 0
    )

    if ($Depth -gt 128) {
        Stop-ProvenanceValidation -Code 'json-depth'
    }
    Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
    if ($Offset.Value -ge $Text.Length) {
        Stop-ProvenanceValidation -Code 'malformed-json'
    }

    $character = $Text[$Offset.Value]
    if ($character -ceq '"') {
        [void] (Read-ProvenanceJsonStringToken -Text $Text -Offset $Offset)
        return
    }
    if ($character -ceq '{') {
        $Offset.Value++
        Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
        $exact = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal
        )
        $folded = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::OrdinalIgnoreCase
        )
        if ($Offset.Value -lt $Text.Length -and
            $Text[$Offset.Value] -ceq '}') {
            $Offset.Value++
            return
        }
        while ($true) {
            Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
            $name = Read-ProvenanceJsonStringToken -Text $Text -Offset $Offset
            if (-not $exact.Add($name) -or -not $folded.Add($name)) {
                Stop-ProvenanceValidation -Code 'duplicate-json-key'
            }
            Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
            if ($Offset.Value -ge $Text.Length -or
                $Text[$Offset.Value] -cne ':') {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
            $Offset.Value++
            Read-ProvenanceJsonValueToken `
                -Text $Text `
                -Offset $Offset `
                -Depth ($Depth + 1)
            Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
            if ($Offset.Value -ge $Text.Length) {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
            if ($Text[$Offset.Value] -ceq '}') {
                $Offset.Value++
                return
            }
            if ($Text[$Offset.Value] -cne ',') {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
            $Offset.Value++
        }
    }
    if ($character -ceq '[') {
        $Offset.Value++
        Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
        if ($Offset.Value -lt $Text.Length -and
            $Text[$Offset.Value] -ceq ']') {
            $Offset.Value++
            return
        }
        while ($true) {
            Read-ProvenanceJsonValueToken `
                -Text $Text `
                -Offset $Offset `
                -Depth ($Depth + 1)
            Move-ProvenanceJsonWhitespace -Text $Text -Offset $Offset
            if ($Offset.Value -ge $Text.Length) {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
            if ($Text[$Offset.Value] -ceq ']') {
                $Offset.Value++
                return
            }
            if ($Text[$Offset.Value] -cne ',') {
                Stop-ProvenanceValidation -Code 'malformed-json'
            }
            $Offset.Value++
        }
    }

    $remaining = $Text.Substring($Offset.Value)
    $literal = [Regex]::Match($remaining, '^(?:true|false|null)')
    if ($literal.Success) {
        $Offset.Value += $literal.Length
        return
    }
    $number = [Regex]::Match(
        $remaining,
        '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
    )
    if (-not $number.Success) {
        Stop-ProvenanceValidation -Code 'malformed-json'
    }
    $Offset.Value += $number.Length
}

function Read-ProvenanceJson {
    param(
        [string] $Path,
        [string] $Code = 'malformed-json'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-ProvenanceValidation -Code 'missing-file'
    }
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        $offset = 0
        Read-ProvenanceJsonValueToken `
            -Text $text `
            -Offset ([ref] $offset)
        Move-ProvenanceJsonWhitespace -Text $text -Offset ([ref] $offset)
        if ($offset -ne $text.Length) {
            Stop-ProvenanceValidation -Code $Code
        }
        return $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        if ($_.Exception.Message.StartsWith(
            'Generated-source provenance validation failed',
            [StringComparison]::Ordinal
        )) {
            throw
        }
        Stop-ProvenanceValidation -Code $Code
    }
}

function ConvertTo-ProvenanceJsonString {
    param([string] $Value)

    $builder = New-Object Text.StringBuilder
    [void] $builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        switch ([int] $character) {
            8 { [void] $builder.Append('\b'); continue }
            9 { [void] $builder.Append('\t'); continue }
            10 { [void] $builder.Append('\n'); continue }
            12 { [void] $builder.Append('\f'); continue }
            13 { [void] $builder.Append('\r'); continue }
            34 { [void] $builder.Append('\"'); continue }
            92 { [void] $builder.Append('\\'); continue }
        }
        $number = [int] $character
        if ($number -lt 0x20 -or $number -gt 0x7e) {
            [void] $builder.Append(
                ('\u{0:x4}' -f $number)
            )
        } else {
            [void] $builder.Append($character)
        }
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-ProvenanceCanonicalJson {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [bool]) {
        if ($Value) {
            return 'true'
        }
        return 'false'
    }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-ProvenanceJsonString -Value ([string] $Value)
    }
    if (Test-ProvenanceInteger -Value $Value) {
        return [Convert]::ToString(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture
        )
    }
    if ($Value -is [Collections.IDictionary]) {
        $members = New-Object 'System.Collections.Generic.List[string]'
        foreach ($key in $Value.Keys) {
            $members.Add((
                (ConvertTo-ProvenanceJsonString -Value ([string] $key)) +
                ':' +
                (ConvertTo-ProvenanceCanonicalJson -Value $Value[$key])
            ))
        }
        return '{' + ($members.ToArray() -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = New-Object 'System.Collections.Generic.List[string]'
        foreach ($item in $Value) {
            $items.Add((ConvertTo-ProvenanceCanonicalJson -Value $item))
        }
        return '[' + ($items.ToArray() -join ',') + ']'
    }

    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $members = New-Object 'System.Collections.Generic.List[string]'
        foreach ($property in $properties) {
            $members.Add((
                (ConvertTo-ProvenanceJsonString -Value $property.Name) +
                ':' +
                (ConvertTo-ProvenanceCanonicalJson -Value $property.Value)
            ))
        }
        return '{' + ($members.ToArray() -join ',') + '}'
    }
    Stop-ProvenanceValidation -Code 'unsupported-json-value'
}

function Write-ProvenanceCanonicalJson {
    param(
        [string] $Path,
        [object] $Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $text = (ConvertTo-ProvenanceCanonicalJson -Value $Value) + "`n"
    [IO.File]::WriteAllText(
        $Path,
        $text,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Test-ProvenanceCommandToken {
    param([object] $Value)

    if (-not ($Value -is [string])) {
        return $false
    }
    $token = [string] $Value
    if (
        [string]::IsNullOrWhiteSpace($token) -or
        $token -cne $token.Trim() -or
        $token.Length -gt 2048 -or
        $token.Contains('\') -or
        $token.Contains(':') -or
        $token.Contains('"') -or
        $token.Contains("'") -or
        $token -match '[^\x20-\x7e]' -or
        $token -match '(?i)(?:^|=)[A-Z]:/' -or
        $token -match '(?:^|=)/' -or
        $token -match '(?i)^[A-Z][A-Z0-9+.-]*://' -or
        $token -match '(?:^|/)\.\.?($|/)'
    ) {
        return $false
    }
    return $true
}

function Test-ProvenanceArtifact {
    param(
        [object] $Artifact,
        [string] $SourceRoot,
        [string] $Code
    )

    Test-ProvenanceExactProperties `
        -Value $Artifact `
        -Names @('path', 'sha256') `
        -Code $Code
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceRelativePath -Value $Artifact.path) `
        -Code $Code
    Assert-ProvenanceCondition `
        -Condition (Test-ProvenanceHash -Value $Artifact.sha256) `
        -Code $Code
    $fullPath = Resolve-ProvenanceSourcePath `
        -SourceRoot $SourceRoot `
        -RelativePath $Artifact.path
    Assert-ProvenanceCondition `
        -Condition (
            (Get-ProvenanceSha256 -Path $fullPath) -ceq
                [string] $Artifact.sha256
        ) `
        -Code $Code
}
