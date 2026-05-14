function Invoke-InputModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $request = $InputData.request
    $targetUrl = [string]$request.target_url
    $auditActionRaw = if ($request.audit_action) { [string]$request.audit_action } else { "START" }
    $auditAction = $auditActionRaw.Trim().ToUpperInvariant()
    if ($auditAction -notin @("START", "NEXT", "FINAL_SUMMARY")) {
        return @{ status = "FAIL"; data = @{ error_code = "INPUT_INVALID_AUDIT_ACTION"; error_message = "audit_action must be START, NEXT, or FINAL_SUMMARY" } }
    }

    $batchSize = 250
    if ($null -ne $request.batch_size -and [int]$request.batch_size -gt 0) {
        $batchSize = [int]$request.batch_size
    }
    if ($batchSize -gt 250) { $batchSize = 250 }

    $autoAudit = $false
    if ($null -ne $request.auto_audit) { $autoAudit = [bool]$request.auto_audit }

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
            scan_profile = "BATCH"
            max_routes = 5000
            max_depth = 2
            hard_cap_routes = 5000
            audit_action = $auditAction
            auto_audit = $autoAudit
            batch_size = $batchSize
            session_id = if ($request.session_id) { [string]$request.session_id } else { $null }

            route_allowlist = @(
                foreach ($r in @($request.route_allowlist)) { $r }
            ) | Where-Object { $_ } | Select-Object -Unique

            primary_route = $pagePath
            route_denylist = @($request.route_denylist)
            viewport_profiles = @($request.viewport_profiles)
        }
    }
}
