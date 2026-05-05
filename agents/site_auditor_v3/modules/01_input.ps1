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

    return @{
        status = "OK"
        data = @{
            target_url = $uri.AbsoluteUri.TrimEnd("/")
            base_url = ($uri.Scheme + "://" + $uri.Authority)

            # STRICT: do NOT auto-add deep path
            route_allowlist = @(
                foreach ($r in @($request.route_allowlist)) { $r }
            ) | Where-Object { $_ } | Select-Object -Unique

            primary_route = "/"
            route_denylist = @($request.route_denylist)
            viewport_profiles = @($request.viewport_profiles)
        }
    }
}
