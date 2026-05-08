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
                discovered_routes = @()
                promoted_routes = @()
                next_owner_module = "route_audit"
                required_next_contract = "no execution route feedback available"
            }
        }
    }

    $discoveredCount = if ($er.discovered_count) { [int]$er.discovered_count } else { 0 }
    $routes = @($er.discovered_routes)
    $promoted = @()
    $i = 1

    foreach ($r in $routes) {
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
            baseline_routes_discovered = $baselineCount
            execution_routes_discovered = $discoveredCount
            rejected_routes = if ($er.rejected_count) { [int]$er.rejected_count } else { 0 }
            discovered_routes = $routes
            promoted_routes = $promoted
            next_owner_module = "route_audit"
            required_next_contract = "promote route_feedback.promoted_routes into route_audit.routes before selection/capture decision"
        }
    }
}
