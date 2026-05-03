function Invoke-InputModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $request = $InputData.request
    $targetUrl = [string]$request.target_url

    if ([string]::IsNullOrWhiteSpace($targetUrl)) {
        return @{ status = "FAIL"; data = @{ error_code = "INPUT_EMPTY"; error_message = "target_url is required" } }
    }

    $uri = $null
    $ok = [System.Uri]::TryCreate($targetUrl, [System.UriKind]::Absolute, [ref]$uri)

    if (-not $ok -or $null -eq $uri) {
        return @{ status = "FAIL"; data = @{ error_code = "INPUT_INVALID_URL"; error_message = "target_url must be an absolute URL" } }
    }

    if ($uri.Scheme -notin @("http", "https")) {
        return @{ status = "FAIL"; data = @{ error_code = "INPUT_UNSUPPORTED_SCHEME"; error_message = "Only http/https URLs are supported" } }
    }

    return @{
        status = "OK"
        data = @{
            target_url = $uri.AbsoluteUri.TrimEnd("/")
            base_url = ($uri.Scheme + "://" + $uri.Authority)
            route_allowlist = @($request.route_allowlist)
            route_denylist = @($request.route_denylist)
            viewport_profiles = @($request.viewport_profiles)
        }
    }
}
