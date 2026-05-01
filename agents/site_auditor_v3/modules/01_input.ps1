function Invoke-InputModule {
    param(
        [string]$BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return @{
            status = "FAIL"
            error = "EMPTY_INPUT"
        }
    }

    return @{
        status = "OK"
        data = @{
            base_url = $BaseUrl
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
}
