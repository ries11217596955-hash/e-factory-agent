Set-StrictMode -Version Latest

function Get-IsoUtcNow {
    return [DateTime]::UtcNow.ToString('o')
}

function New-NotImplementedStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component
    )

    return [ordered]@{
        component = $Component
        status = 'NOT_IMPLEMENTED'
        note = 'Reserved for a future sprint.'
    }
}
