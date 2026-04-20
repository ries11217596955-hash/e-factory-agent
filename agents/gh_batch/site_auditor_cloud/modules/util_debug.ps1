function Get-DebugValueSample {
    param(
        [object]$Value,
        [int]$MaxLength = 180
    )

    if ($null -eq $Value) { return '<null>' }

    $text = ''
    if ($Value -is [string]) {
        $text = $Value
    }
    elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        try {
            $text = $Value | ConvertTo-Json -Depth 4 -Compress
        }
        catch {
            $text = [string]$Value
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        try {
            $text = @($Value | Select-Object -First 5 | ForEach-Object { [string]$_ }) -join ', '
        }
        catch {
            $text = [string]$Value
        }
    }
    else {
        $text = [string]$Value
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return '<empty>' }
    if ($text.Length -le $MaxLength) { return $text }
    return "$($text.Substring(0, $MaxLength))..."
}

function Get-ObjectShapeSummary {
    param([object]$Value)

    if ($null -eq $Value) {
        return [ordered]@{
            type = '<null>'
            keys = @()
            property_names = @()
            count = 0
        }
    }

    $keys = @()
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Select-Object -First 20)
    }

    $propertyNames = @($Value.PSObject.Properties.Name | Select-Object -First 20)
    $count = 0
    if ($Value -is [System.Collections.ICollection]) {
        $count = [int]$Value.Count
    }

    return [ordered]@{
        type = $Value.GetType().FullName
        keys = @($keys)
        property_names = @($propertyNames)
        count = $count
    }
}
