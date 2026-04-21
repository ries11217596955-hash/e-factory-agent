function Convert-ToIntSafe {
    param(
        [object]$Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Convert-ToBoolSafe {
    param(
        [object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    $normalized = $text.Trim().ToLowerInvariant()
    if ($normalized -in @('true', '1', 'yes', 'y')) { return $true }
    if ($normalized -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function Convert-ToObjectArraySafe {
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return @() }
    if ($Value -is [object[]]) { return [object[]]$Value }
    if ($Value -is [string[]]) { return [object[]]$Value }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }
    if ($Value -is [System.Collections.Generic.List[object]]) { return [object[]]$Value.ToArray() }
    if ($Value -is [System.Collections.Generic.List[string]]) { return [object[]]$Value.ToArray() }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        return @($Value)
    }
    if ($Value -is [System.Collections.ICollection]) {
        $materialized = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $materialized.Add($item)
        }
        return [object[]]$materialized.ToArray()
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $materialized = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $materialized.Add($item)
        }
        return [object[]]$materialized.ToArray()
    }
    return @($Value)
}

function Normalize-ToArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        return @([string]$Value)
    }

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        return @($Value)
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            [void]$items.Add($item)
        }
        return @($items.ToArray())
    }

    return @($Value)
}

function Normalize-CollectionShape {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) { return @($Value) }
    return Convert-ToObjectArraySafe -Value $Value
}

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if ($null -eq $List) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if (-not ($List.Contains($text))) {
        $List.Add($text)
    }
}

function Convert-ToStringArraySafe {
    param(
        [object]$Value
    )

    $items = Convert-ToObjectArraySafe -Value $Value
    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($item in $items) {
        if ($null -eq $item) { continue }

        if ($item -is [System.Collections.IDictionary] -or $item -is [PSCustomObject]) {
            $json = $item | ConvertTo-Json -Depth 8 -Compress
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $normalized.Add([string]$json)
            }
            continue
        }

        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $normalized.Add($text)
        }
    }

    if ($normalized.Count -eq 0) { return @() }
    return [string[]]$normalized.ToArray()
}

function Convert-ToStringKeyDictionarySafe {
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return @{} }
    if (-not ($Value -is [System.Collections.IDictionary])) { return $Value }

    $normalized = [ordered]@{}
    foreach ($entry in @($Value.GetEnumerator() | Where-Object { $_ -ne $null })) {
        $keyText = [string](Safe-Get -Object $entry -Key 'Key' -Default '')
        if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
        $normalized[$keyText] = Safe-Get -Object $entry -Key 'Value' -Default $null
    }

    return $normalized
}

function Convert-ToHashtableSafe {
    param([object]$Value)

    if ($null -eq $Value) { return @{} }
    if ($Value -is [System.Collections.IDictionary]) {
        $normalized = [ordered]@{}
        foreach ($entry in @($Value.GetEnumerator())) {
            $keyText = [string](Safe-Get -Object $entry -Key 'Key' -Default '')
            if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
            $normalized[$keyText] = Safe-Get -Object $entry -Key 'Value' -Default $null
        }
        return $normalized
    }

    if ($Value -is [PSCustomObject]) {
        $normalized = [ordered]@{}
        foreach ($prop in @($Value.PSObject.Properties)) {
            if ($null -eq $prop) { continue }
            $keyText = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
            $normalized[$keyText] = $prop.Value
        }
        return $normalized
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $materialized = @(Convert-ToObjectArraySafe -Value $Value)
        if ($materialized.Count -eq 0) {
            return @{}
        }
        if ($materialized.Count -eq 1) {
            return Convert-ToHashtableSafe -Value $materialized[0]
        }
    }

    Write-Host "[WARN] Convert-ToHashtableSafe fallback triggered. Type: $($Value.GetType().FullName)"
    return @{ __raw = $Value }
}
