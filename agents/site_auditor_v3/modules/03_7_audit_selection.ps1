function Invoke-Module037AuditSelection {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $baselineSelection = $InputData.selection
    $routePromotion = $InputData.route_promotion

    $promotionApplied = ($routePromotion -and $routePromotion.promotion_applied -eq $true -and $routePromotion.promoted_selection)
    $action = if ($baselineSelection -and $baselineSelection.audit_action) { [string]$baselineSelection.audit_action } else { "START" }
    $batchSize = if ($baselineSelection -and $null -ne $baselineSelection.batch_size) { [int]$baselineSelection.batch_size } else { 0 }
    $selectedUrls = if ($baselineSelection -and $baselineSelection.selected_urls) { @($baselineSelection.selected_urls | ForEach-Object { [string]$_ }) } else { @() }

    $inventoryRoutes = if ($promotionApplied) {
        @($routePromotion.promoted_selection.selected)
    } elseif ($PipelineState.route_audit -and $PipelineState.route_audit.routes) {
        @($PipelineState.route_audit.routes)
    } else {
        @($baselineSelection.selected)
    }

    if ($action -eq "START") {
        $inventoryUrls = @($inventoryRoutes | ForEach-Object { [string]$_.url })
        $selectedUrls = @($inventoryUrls | Select-Object -First $batchSize)
        $nextPending = @($inventoryUrls | Where-Object { $selectedUrls -notcontains $_ })

        if ($baselineSelection -and $baselineSelection.session_ledger_path) {
            $ledgerPath = [string]$baselineSelection.session_ledger_path
            if (Test-Path -LiteralPath $ledgerPath) {
                $ledger = Get-Content -Path $ledgerPath -Raw | ConvertFrom-Json -AsHashtable
                $ledger.inventory_url_count = $inventoryUrls.Count
                $ledger.pending_urls = $inventoryUrls
                $ledger.coverage_percent = 0
                $ledger.next_action = if ($nextPending.Count -eq 0) { "FINAL_SUMMARY" } else { "NEXT_BATCH" }
                $ledger | ConvertTo-Json -Depth 30 | Set-Content -Path $ledgerPath -Encoding UTF8
            }
        }
    }

    $selectedRoutes = if ($action -eq "FINAL_SUMMARY") {
        @()
    } else {
        @($inventoryRoutes | Where-Object { $selectedUrls -contains [string]$_.url })
    }

    $nextPendingCount = if ($action -eq "START") {
        @($inventoryRoutes | ForEach-Object { [string]$_.url } | Where-Object { $selectedUrls -notcontains $_ }).Count
    } elseif ($baselineSelection -and $null -ne $baselineSelection.next_pending_count) {
        [int]$baselineSelection.next_pending_count
    } else {
        0
    }

    return @{
        status = "OK"
        data = [ordered]@{
            source = "03_7_audit_selection"
            audit_selection_source = if ($promotionApplied) { "promoted_selection" } else { "baseline_selection" }
            promotion_applied = [bool]$promotionApplied

            # Session continuity truth is owned by 03_selection and must survive
            # route-promotion replacement of the selection payload.
            audit_action = $action
            session_id = if ($baselineSelection) { [string]$baselineSelection.session_id } else { $null }
            session_ledger_path = if ($baselineSelection) { [string]$baselineSelection.session_ledger_path } else { $null }
            batch_size = $batchSize
            next_pending_count = $nextPendingCount
            auto_audit = if ($baselineSelection -and $null -ne $baselineSelection.auto_audit) { [bool]$baselineSelection.auto_audit } else { $false }

            selected_urls = @($selectedUrls)
            baseline_selection_count = if ($baselineSelection -and $baselineSelection.totals) { [int]$baselineSelection.totals.selected } else { 0 }
            promoted_selection_count = if ($routePromotion -and $routePromotion.promoted_selection -and $routePromotion.promoted_selection.totals) { [int]$routePromotion.promoted_selection.totals.selected } else { 0 }
            selected = @($selectedRoutes)
            rejected = @()
            totals = [ordered]@{ selected = $selectedRoutes.Count; rejected = 0 }
        }
    }
}
