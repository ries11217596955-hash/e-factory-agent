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

            # Session continuity truth is owned by 03_selection and must survive
            # route-promotion replacement of the selection payload.
            audit_action = if ($baselineSelection) { [string]$baselineSelection.audit_action } else { $null }
            session_id = if ($baselineSelection) { [string]$baselineSelection.session_id } else { $null }
            session_ledger_path = if ($baselineSelection) { [string]$baselineSelection.session_ledger_path } else { $null }
            batch_size = if ($baselineSelection -and $null -ne $baselineSelection.batch_size) { [int]$baselineSelection.batch_size } else { 0 }
            next_pending_count = if ($baselineSelection -and $null -ne $baselineSelection.next_pending_count) { [int]$baselineSelection.next_pending_count } else { 0 }
            auto_audit = if ($baselineSelection -and $null -ne $baselineSelection.auto_audit) { [bool]$baselineSelection.auto_audit } else { $false }

            baseline_selection_count = if ($baselineSelection -and $baselineSelection.totals) { [int]$baselineSelection.totals.selected } else { 0 }
            promoted_selection_count = if ($routePromotion -and $routePromotion.promoted_selection -and $routePromotion.promoted_selection.totals) { [int]$routePromotion.promoted_selection.totals.selected } else { 0 }
            selected = @($selectedRoutes)
            rejected = @()
            totals = [ordered]@{ selected = $selectedRoutes.Count; rejected = 0 }
        }
    }
}
