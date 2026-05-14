function Invoke-SelectionModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $inputState = $InputData.input
    $routeAudit = $InputData.route_audit
    $routes = @($routeAudit.routes)
    $action = [string]$inputState.audit_action
    $batchSize = [int]$inputState.batch_size
    $sessionsRoot = "agents/site_auditor_v3/runs/sessions"
    New-Item -ItemType Directory -Force -Path $sessionsRoot | Out-Null

    $sessionId = if ($inputState.session_id) { [string]$inputState.session_id } else { "sess_" + [string](Get-Date -Format "yyyyMMdd_HHmmss") }
    $sessionRoot = Join-Path $sessionsRoot $sessionId
    $ledgerPath = Join-Path $sessionRoot "AUDIT_SESSION_LEDGER.json"

    if ($action -eq "START") {
        $pendingUrls = @($routes | ForEach-Object { [string]$_.url })
        $selectedUrls = @($pendingUrls | Select-Object -First $batchSize)
        $selected = @($routes | Where-Object { $selectedUrls -contains $_.url })
        $nextPending = @($pendingUrls | Where-Object { $selectedUrls -notcontains $_ })
        New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null
        $ledger = [ordered]@{
            session_id = $sessionId
            base_url = [string]$inputState.base_url
            target_url = [string]$inputState.target_url
            inventory_url_count = $pendingUrls.Count
            batch_size = $batchSize
            audited_urls = @()
            pending_urls = $pendingUrls
            failed_urls = @()
            completed_batch_ids = @()
            batch_history = @()
            last_completed_run_id = $null
            aggregate_findings = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
            cumulative_findings = @()
            cumulative_finding_actions = @()
            future_report_streams = @()
            coverage_percent = 0
            next_action = if ($nextPending.Count -eq 0) { "FINAL_SUMMARY" } else { "NEXT_BATCH" }
            auto_audit = [bool]$inputState.auto_audit
        }
        $ledger | ConvertTo-Json -Depth 30 | Set-Content -Path $ledgerPath -Encoding UTF8
    } else {
        if (-not (Test-Path -LiteralPath $ledgerPath)) {
            return @{ status = "FAIL"; data = @{ error_code = "LEDGER_NOT_FOUND"; error_message = "session ledger not found for action $action" } }
        }
        $ledger = Get-Content -Path $ledgerPath -Raw | ConvertFrom-Json -AsHashtable
        $pendingUrls = @($ledger.pending_urls)
        $selectedUrls = @($pendingUrls | Select-Object -First ([int]$ledger.batch_size))
        $selected = @($routes | Where-Object { $selectedUrls -contains $_.url })
        $nextPending = @($pendingUrls | Where-Object { $selectedUrls -notcontains $_ })
    }

    return @{
        status = "OK"
        data = @{
            selected = $selected
            selected_urls = @($selectedUrls)
            rejected = @()
            totals = @{
                selected = $selected.Count
                rejected = 0
            }
            audit_action = $action
            session_id = $sessionId
            session_ledger_path = $ledgerPath
            batch_size = $batchSize
            next_pending_count = $nextPending.Count
            auto_audit = [bool]$inputState.auto_audit
        }
    }
}
