function Invoke-Module08RoutePromotion {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $feedback = $InputData.route_feedback
    $baseline = if ($PipelineState.route_audit) { $PipelineState.route_audit } else { $null }

    $baselineRoutes = @()
    if ($baseline -and $baseline.routes) {
        $baselineRoutes = @($baseline.routes)
    }

    $promotedRoutes = @()
    if ($feedback -and $feedback.promoted_routes) {
        $promotedRoutes = @($feedback.promoted_routes)
    }
    $assetsExcludedCount = if ($feedback -and $null -ne $feedback.assets_excluded_count) { [int]$feedback.assets_excluded_count } else { 0 }

    $usePromotion = ($feedback -and $feedback.available -eq $true -and $promotedRoutes.Count -gt $baselineRoutes.Count)

    $routesForAudit = if ($usePromotion) { $promotedRoutes } else { $baselineRoutes }

    $promotedRouteAudit = [ordered]@{
        source = if ($usePromotion) { "route_feedback.promoted_routes" } else { "route_audit.routes" }
        promotion_applied = [bool]$usePromotion
        routes = $routesForAudit
        routes_original = $baselineRoutes
        routes_promoted_count = $promotedRoutes.Count
        assets_excluded_count = $assetsExcludedCount
        routes_baseline_count = $baselineRoutes.Count
        totals = [ordered]@{
            discovered = $routesForAudit.Count
            eligible = $routesForAudit.Count
            excluded = 0
        }
    }

    $promotedSelection = [ordered]@{
        source = "route_promotion.promoted_route_audit.routes"
        promotion_applied = [bool]$usePromotion
        selected = $routesForAudit
        rejected = @()
        totals = [ordered]@{
            selected = $routesForAudit.Count
            rejected = 0
        }
    }

    return @{
        status = "OK"
        data = [ordered]@{
            source = "08_route_promotion"
            promotion_applied = [bool]$usePromotion
            reason = if ($usePromotion) { "route_feedback has more routes than baseline route_audit" } else { "baseline route_audit remains authoritative" }
            promoted_route_audit = $promotedRouteAudit
            promoted_selection = $promotedSelection
            ready_for_promoted_capture = [bool]($routesForAudit.Count -gt $baselineRoutes.Count)
            next_owner_module = "capture"
            required_next_contract = "capture should consume route_promotion.promoted_selection before final decision"
        }
    }
}
