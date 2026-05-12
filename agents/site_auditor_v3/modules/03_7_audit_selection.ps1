function Invoke-Module037AuditSelection {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $baselineSelection = $InputData.selection
    $routePromotion = $InputData.route_promotion

    $promotionApplied = ($routePromotion -and $routePromotion.promotion_applied -eq $true -and $routePromotion.promoted_selection)
    $selectedBlock = if ($promotionApplied) { $routePromotion.promoted_selection } else { $baselineSelection }

    $selectedRoutes = @($selectedBlock.selected)

    return @{
        status = "OK"
        data = [ordered]@{
            source = "03_7_audit_selection"
            audit_selection_source = if ($promotionApplied) { "promoted_selection" } else { "baseline_selection" }
            promotion_applied = [bool]$promotionApplied
            baseline_selection_count = if ($baselineSelection -and $baselineSelection.totals) { [int]$baselineSelection.totals.selected } else { 0 }
            promoted_selection_count = if ($routePromotion -and $routePromotion.promoted_selection -and $routePromotion.promoted_selection.totals) { [int]$routePromotion.promoted_selection.totals.selected } else { 0 }
            selected = @($selectedRoutes)
            rejected = @()
            totals = [ordered]@{ selected = $selectedRoutes.Count; rejected = 0 }
        }
    }
}
