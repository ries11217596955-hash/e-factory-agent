function Invoke-InputModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $request = $InputData.request
    $targetUrl = [string]$request.target_url
    $scanProfileRaw = if ($request.scan_profile) { [string]$request.scan_profile } else { "STANDARD" }
    $scanProfile = $scanProfileRaw.Trim().ToUpperInvariant()

    if ($scanProfile -notin @("STANDARD", "DEEP")) {
        return @{ status = "FAIL"; data = @{ error_code = "INPUT_INVALID_SCAN_PROFILE"; error_message = "scan_profile must be STANDARD or DEEP" } }
    }

    $maxRoutes = if ($scanProfile -eq "DEEP") { 150 } else { 50 }
    $maxDepth = if ($scanProfile -eq "DEEP") { 3 } else { 2 }

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

    $pagePath = $uri.AbsolutePath
    if ([string]::IsNullOrWhiteSpace($pagePath)) { $pagePath = "/" }
    if (-not $pagePath.StartsWith("/")) { $pagePath = "/" + $pagePath }
    if (($pagePath.Length -gt 1) -and $pagePath.EndsWith("/")) { $pagePath = $pagePath.TrimEnd("/") }

    $normalizedTargetUrl = ($uri.Scheme + "://" + $uri.Authority + $pagePath)
    if ($normalizedTargetUrl.EndsWith("/") -and $pagePath -eq "/") {
        $normalizedTargetUrl = $normalizedTargetUrl.TrimEnd("/")
    }

    return @{
        status = "OK"
        data = @{
            target_url = $normalizedTargetUrl
            base_url = ($uri.Scheme + "://" + $uri.Authority)
            scan_profile = $scanProfile
            max_routes = $maxRoutes
            max_depth = $maxDepth
            hard_cap_routes = 200

            route_allowlist = @(
                foreach ($r in @($request.route_allowlist)) { $r }
            ) | Where-Object { $_ } | Select-Object -Unique

            primary_route = $pagePath
            route_denylist = @($request.route_denylist)
            viewport_profiles = @($request.viewport_profiles)
        }
    }
}
