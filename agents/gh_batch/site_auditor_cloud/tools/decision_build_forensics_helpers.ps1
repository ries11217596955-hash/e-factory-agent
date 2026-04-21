function Convert-ToDecisionWarningStringArray {
    param([object]$Value)

    $result = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Value) {
        return @()
    }

    try {
        foreach ($item in $Value) {

            if ($null -eq $item) { continue }

            $text = [string]$item

            if ([string]::IsNullOrWhiteSpace($text)) { continue }

            $result.Add($text)
        }
    }
    catch {
        $text = [string]$Value

        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $result.Add($text)
        }
    }

    return @($result.ToArray())
}
