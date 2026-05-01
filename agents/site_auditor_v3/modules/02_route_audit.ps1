function Invoke-RouteAuditModule {
    param(
        [hashtable]$InputData
    )

    if ($InputData.status -ne "OK") {
        return @{
            status = "SKIP"
            reason = "INPUT_NOT_OK"
        }
    }

    $baseUrl = $InputData.data.base_url

    return @{
        status = "OK"
        routes = @(
            "$baseUrl/"
        )
    }
}
