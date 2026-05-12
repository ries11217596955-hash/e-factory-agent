function Invoke-Module08RouteFeedback {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $execution = $InputData.execution
    $routeAudit = if ($PipelineState.route_audit) { $PipelineState.route_audit } else { $null }

    $baselineCount = 0
    if ($routeAudit -and $routeAudit.totals -and $null -ne $routeAudit.totals.discovered) {
        $baselineCount = [int]$routeAudit.totals.discovered
    }

    $er = $null
    if ($execution -and $execution.execution_result -and $execution.execution_result.data) {
        $er = $execution.execution_result.data
    }

    if (-not $er) {
        return @{
            status = "OK"
            data = [ordered]@{
                source = "execution.route_discovery"
                available = $false
                baseline_routes_discovered = $baselineCount
                execution_routes_discovered = 0
                rejected_routes = 0
                rejected_routes_count = 0
                rejected_route_details = @()
                discovered_routes = @()
                promoted_routes = @()
                next_owner_module = "route_audit"
                required_next_contract = "no execution route feedback available"
            }
        }
    }

    $discoveredCount = if ($er.discovered_count) { [int]$er.discovered_count } else { 0 }
    $pagesDiscoveredCount = if ($null -ne $er.pages_discovered_count) { [int]$er.pages_discovered_count } else { $discoveredCount }
    $assetsExcludedCount = if ($null -ne $er.assets_excluded_count) { [int]$er.assets_excluded_count } else { 0 }
    $rejectedCount = if ($er.rejected_count) { [int]$er.rejected_count } else { 0 }
    $pageRoutes = if ($er.page_routes) { @($er.page_routes) } else { @($er.discovered_routes) }
    $assetRoutes = if ($er.asset_routes) { @($er.asset_routes) } else { @() }
    $rejectedDetails = @($er.rejected_routes)
    $promoted = @()
    $i = 1

    foreach ($r in $pageRoutes) {
        if (-not $r.path -or -not $r.url) { continue }
        $promoted += [ordered]@{
            route_id = ("R{0:D3}" -f $i)
            path = [string]$r.path
            url = [string]$r.url
            eligible = $true
            source = "execution.route_discovery"
        }
        $i++
    }

    return @{
        status = "OK"
        data = [ordered]@{
            source = "execution.route_discovery"
            available = ($discoveredCount -gt $baselineCount)
            discovery_sources = if ($er.discovery_sources) { @($er.discovery_sources) } else { @("baseline_candidates") }
            scope_status = if ($er.scope_status) { [string]$er.scope_status } else { "PARTIAL" }
            scope_reason = if ($er.scope_reason) { [string]$er.scope_reason } else { "scope_truth_unavailable" }
            baseline_routes_discovered = $baselineCount
            execution_routes_discovered = $discoveredCount
            checked_count = if ($null -ne $er.checked_count) { [int]$er.checked_count } else { 0 }
            pages_discovered_count = $pagesDiscoveredCount
            assets_excluded_count = $assetsExcludedCount
            rejected_routes = $rejectedCount
            rejected_routes_count = $rejectedCount
            rejected_route_details = $rejectedDetails
            asset_route_details = $assetRoutes
            page_route_details = $pageRoutes
            discovered_routes = $pageRoutes
            promoted_routes = $promoted
            next_owner_module = "route_audit"
            required_next_contract = "promote route_feedback.promoted_routes into route_audit.routes before selection/capture decision"
        }
    }
}
