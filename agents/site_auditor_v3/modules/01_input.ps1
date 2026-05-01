function Invoke-InputModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $request = $InputData.request
    $targetUrl = [string]$request.target_url

    if ([string]::IsNullOrWhiteSpace($targetUrl)) {
        return @{
            status = "FAIL"
            data = @{
                error = "target_url is required"
            }
        }
    }

    return @{
        status = "OK"
        data = @{
            target_url = $targetUrl
            base_url = $targetUrl.TrimEnd("/")
            route_allowlist = @($request.route_allowlist)
            route_denylist = @($request.route_denylist)
            viewport_profiles = @($request.viewport_profiles)
        }
    }
}
