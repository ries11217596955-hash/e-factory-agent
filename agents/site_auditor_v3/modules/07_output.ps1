. (Resolve-Path "agents/site_auditor_v3/lib/operator_control.ps1").Path
. (Resolve-Path "agents/site_auditor_v3/lib/decision_next_step.ps1").Path
. (Resolve-Path "agents/site_auditor_v3/lib/agent_map_builder.ps1").Path

function Invoke-Module07Output {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $runId = if ($PipelineState.run.run_id) { [string]$PipelineState.run.run_id } else { "manual-smoke" }
    $runRoot = Join-Path "agents/site_auditor_v3/runs" $runId

    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

    $pipelineStatus = [ordered]@{}
    foreach ($key in @("input","route_audit","selection","capture","reconcile","decision","output")) {
        if ($PipelineState.ContainsKey($key)) { $pipelineStatus[$key] = "OK" }
        else { $pipelineStatus[$key] = "SKIPPED" }
    }

    $diag = if ($PipelineState.decision -and $PipelineState.decision.self_diagnostic) {
        $PipelineState.decision.self_diagnostic
    } else {
        [ordered]@{
            failed_stage = $PipelineState.run.failed_module
            what_worked = @()
            what_failed = @($PipelineState.run.failed_module)
            limitations = @("pipeline stopped before decision")
            evidence_gaps = @("decision_not_generated")
            confidence = "LOW"
            next_debug_step = "Inspect failed module output in RUN_REPORT"
            next_build_step = "Harden FAIL routing and diagnostic fallback"
            forbidden_next_steps = @(
                "do not treat invalid input as audit PASS",
                "do not continue after input failure",
                "do not ship runpack without diagnostic_summary"
            )
        }
    }

    $cap = if ($PipelineState.decision -and $PipelineState.decision.self_build) {
        $PipelineState.decision.self_build
    } else {
        [ordered]@{
            missing_capabilities = @("fail_path_diagnostic_generation")
            weak_capabilities = @()
            next_capability_to_build = "fail_path_diagnostic_generation"
            reason = "pipeline stopped before decision layer"
        }
    }


    $decisionData = if ($PipelineState.decision) { $PipelineState.decision } else { $null }
    $verdict = if ($decisionData -and $decisionData.audit_verdict) { [string]$decisionData.audit_verdict } else { "INCONCLUSIVE" }
    $score = if ($decisionData -and $null -ne $decisionData.score) { [int]$decisionData.score } else { 0 }
    $limitations = New-Object System.Collections.ArrayList
    if ($decisionData -and $decisionData.limitations) {
        foreach ($item in @($decisionData.limitations)) {
            [void]$limitations.Add([string]$item)
        }
    } elseif (-not $decisionData) {
        [void]$limitations.Add("decision_module_not_run")
    }
    $findingCounts = if ($decisionData -and $decisionData.finding_counts) { $decisionData.finding_counts } else { [ordered]@{ critical=0; high=0; medium=0; low=0 } }
    $evidenceQuality = if ($PipelineState.reconcile -and $PipelineState.reconcile.evidence_quality) {
        $PipelineState.reconcile.evidence_quality
    } else {
        "UNKNOWN"
    }
    $decisionReason = if ($decisionData -and $decisionData.decision_reason) { @($decisionData.decision_reason) } else { @("Decision module unavailable; diagnostic fallback emitted") }
    $decision = if ($decisionData) { $decisionData } else { [ordered]@{ status = "NOT_RUN"; source = "07_output_fallback" } }

    $routeDiscoveryResult = $null
    $handlerPath = "agents/site_auditor_v3/modules/internal_command_handlers.ps1"
    if (Test-Path -LiteralPath $handlerPath) {
        . (Resolve-Path $handlerPath).Path
        $discovery = Invoke-InternalCommand -Command @{ type="internal"; handler="route_discovery"; args=@{} } -PipelineState $PipelineState
        if ($discovery -and $discovery.status -eq "OK") {
            $routeDiscoveryResult = $discovery.data
        }
    }

    $task = $null
    if ($PipelineState.execution -and $PipelineState.execution.execution_result -and $PipelineState.execution.execution_result.data -and $PipelineState.execution.execution_result.data.result) {
        $task = $PipelineState.execution.execution_result.data.result
    }
    else {
        $handlerPath = (Resolve-Path "agents/site_auditor_v3/modules/internal_command_handlers.ps1").Path
        . $handlerPath
        $internalCommand = @{ type = "internal"; handler = "prepare_capability_task"; args = @{} }
        $internalResult = Invoke-InternalCommand -Command $internalCommand -PipelineState $PipelineState
        if ($internalResult -and $internalResult.status -eq "OK" -and $internalResult.data -and $internalResult.data.result) {
            $task = $internalResult.data.result
        }
    }


    $fallbackDecisionAction = [ordered]@{
        action_id = "repair_failed_module"
        action = "repair failed module before continuing"
        why = "pipeline stopped before decision layer"
        target_module = if ($PipelineState.run -and $PipelineState.run.failed_module) { $PipelineState.run.failed_module } else { "unknown" }
        source = "07_output_fail_path_fallback"
        priority = "highest"
        next_command_hint = "inspect failed module output in RUN_REPORT"
    }

    $decisionNextStep = New-SiteAuditorV3DecisionNextStepBlock -PipelineState $PipelineState -FallbackDecisionAction $fallbackDecisionAction
    $safeDecisionAction = $decisionNextStep.decision_action
    $safeNextStep = $decisionNextStep.next_step

    $operatorControl = New-SiteAuditorV3OperatorControlBlock

    $report = [ordered]@{
        run_id = $runId
        verdict = $verdict
        score = $score
        limitations = $limitations
        finding_counts = $findingCounts
        evidence_quality = $evidenceQuality
        decision_reason = $decisionReason
        decision = $decision
        self_build = $cap
        self_diagnostic = $diag

        read_me_first = $true
        operator_control = $operatorControl

        identity = [ordered]@{
            agent = "SITE_AUDITOR_V3"
            mode = "BUILD"
            run_id = $runId
            current_stage = "RUN_REPORT_REENTRY_V1"
        }

        packaging = [ordered]@{
            mode = "RAW_RUN"
            runpack_expected = $false
            runpack_created = $false
            deliverable = $null
            note = "Direct run.ps1 execution creates RUN_REPORT/TASK only. Use tests/run_and_validate.sh for packaged runpack ZIP."
        }

        mission = [ordered]@{
            goal = "input -> weak points -> evidence -> decision -> action -> next capability"
            forbidden = @("silent fail","fake PASS","decision without evidence","output inventing findings")
        }

        build_discipline = [ordered]@{
            rule = "Build capability packs, not one-off isolated checks."
            means = @(
                "A single finding is a signal to strengthen an existing owner layer or a whole rule pack.",
                "Do not create a new module for every finding type.",
                "When a capability class is clear, design the pack path: evidence -> findings -> actions -> validator -> report."
            )
            forbidden = @(
                "one-parameter-at-a-time auditor construction as the default mode",
                "module proliferation for isolated symptoms",
                "micro-patching a single check when the owner gap is a whole capability class"
            )
        }

        operator_instruction = [ordered]@{
            for_chatgpt = "Read this RUN_REPORT.json first. Do not guess. Use read_order, if_problem_then_read, operator_control.function_done_gate, and build_discipline. Choose one bottleneck and one next step. Do not close any step until function_done_gate is satisfied. Build capability packs, not one-off checks."
            for_agent = "Return a usable result or a diagnostic. Declare missing capability instead of pretending."
            for_owner = "This file explains what happened, what to read, what to do next, and which Function Done-Gate checks must pass before a step is closed."
        }

        read_order = @(
            "RUN_REPORT.json",
            "agents/site_auditor_v3/docs/PRODUCT_MEMORY.md",
            "agents/site_auditor_v3/docs/CAPABILITY_MAP.md",
            "agents/site_auditor_v3/docs/INPUT_MODES.md",
            "agents/site_auditor_v3/docs/RUN_REPORT_REQUIREMENTS.md",
            "agents/site_auditor_v3/contracts/module_registry.json"
        )

        if_problem_then_read = [ordered]@{
            forgot_product_goal = "agents/site_auditor_v3/docs/PRODUCT_MEMORY.md"
            forgot_capabilities = "agents/site_auditor_v3/docs/CAPABILITY_MAP.md"
            input_mode_question = "agents/site_auditor_v3/docs/INPUT_MODES.md"
            report_contract_question = "agents/site_auditor_v3/docs/RUN_REPORT_REQUIREMENTS.md"
            pipeline_or_module_question = "agents/site_auditor_v3/contracts/module_registry.json"
        }

        pipeline_status = $pipelineStatus

        audit_result = [ordered]@{
            verdict = $verdict
            score = $score
            data_quality = if ($PipelineState.decision) { $PipelineState.decision.data_quality } else { "FAILED" }
            finding_counts = $findingCounts
            decision_reason = $decisionReason
        }

        evidence_summary = [ordered]@{
            routes_discovered = if ($PipelineState.route_audit) { $PipelineState.route_audit.totals.discovered } else { 0 }
            routes_selected = if ($PipelineState.selection) { $PipelineState.selection.totals.selected } else { 0 }
            baseline_selection_count = if ($PipelineState.selection -and $null -ne $PipelineState.selection.baseline_selection_count) { [int]$PipelineState.selection.baseline_selection_count } else { if ($PipelineState.selection) { [int]$PipelineState.selection.totals.selected } else { 0 } }
            promoted_selection_count = if ($PipelineState.selection -and $null -ne $PipelineState.selection.promoted_selection_count) { [int]$PipelineState.selection.promoted_selection_count } else { 0 }
            audit_selection_source = if ($PipelineState.selection -and $PipelineState.selection.audit_selection_source) { [string]$PipelineState.selection.audit_selection_source } else { "baseline_selection" }
            capture_requested_count = if ($PipelineState.capture) { [int]$PipelineState.capture.totals.requested } else { 0 }
            route_coverage_truth = if ($PipelineState.selection) { [ordered]@{ selected_routes = [int]$PipelineState.selection.totals.selected; coverage_rows = if ($PipelineState.reconcile) { @($PipelineState.reconcile.coverage).Count } else { 0 } } } else { $null }
            captures_requested = if ($PipelineState.capture) { $PipelineState.capture.totals.requested } else { 0 }
            captures_succeeded = if ($PipelineState.capture) { $PipelineState.capture.totals.succeeded } else { 0 }
            coverage_status = if ($PipelineState.reconcile) { $PipelineState.reconcile.status } else { "NOT_RUN" }
            gaps_count = if ($PipelineState.reconcile) { @($PipelineState.reconcile.gaps).Count } else { 0 }
            evidence_quality = $evidenceQuality
            findings = if ($PipelineState.reconcile -and $PipelineState.reconcile.findings) { $PipelineState.reconcile.findings } else { @() }
            finding_actions = if ($PipelineState.reconcile -and $PipelineState.reconcile.finding_actions) { $PipelineState.reconcile.finding_actions } else { @() }
            visual_capture = if ($PipelineState.visual_capture) { $PipelineState.visual_capture } else { $null }
            route_feedback = if ($PipelineState.route_feedback) { $PipelineState.route_feedback } else { [ordered]@{
                source = "execution.route_discovery"
                available = $false
                discovery_sources = @()
                scope_status = "PARTIAL"
                scope_reason = "route_feedback_missing"
                baseline_routes_discovered = if ($PipelineState.route_audit -and $PipelineState.route_audit.totals) { [int]$PipelineState.route_audit.totals.discovered } else { 0 }
                execution_routes_discovered = 0
                checked_count = 0
                pages_discovered_count = 0
                assets_excluded_count = 0
                rejected_routes = 0
                rejected_routes_count = 0
                rejected_route_details = @()
                asset_route_details = @()
                page_route_details = @()
                discovered_routes = @()
                promoted_routes = @()
                next_owner_module = "route_audit"
                required_next_contract = "no route_feedback state available"
            } }
            route_promotion = if ($PipelineState.route_promotion) { $PipelineState.route_promotion } else { [ordered]@{
                source = "08_route_promotion"
                promotion_applied = $false
                reason = "no route_promotion state available"
                promoted_route_audit = $null
                promoted_selection = $null
                ready_for_promoted_capture = $false
                next_owner_module = "capture"
                required_next_contract = "no route promotion available"
            } }
        }

        audit_session = [ordered]@{
            session_id = if ($PipelineState.selection -and $PipelineState.selection.session_id) { [string]$PipelineState.selection.session_id } else { $null }
            audit_action = if ($PipelineState.selection -and $PipelineState.selection.audit_action) { [string]$PipelineState.selection.audit_action } else { "START" }
            batch_size = if ($PipelineState.selection -and $null -ne $PipelineState.selection.batch_size) { [int]$PipelineState.selection.batch_size } else { 250 }
            batch_audited_count = if ($PipelineState.selection -and $PipelineState.selection.totals) { [int]$PipelineState.selection.totals.selected } else { 0 }
            total_audited_count = 0
            total_pending_count = 0
            coverage_percent = 0
            next_action = "NEXT_BATCH"
        }

        session_summary = $null
        current_batch_summary = $null

        diagnostic_summary = $diag
        agent_capability_state = $cap

        agent_map = [ordered]@{
            json = "AGENT_MAP.json"
            markdown = "AGENT_MAP.md"
        }

        decision_action = $safeDecisionAction
        execution = if ($PipelineState.execution) { $PipelineState.execution } else { $null }
          build = if ($PipelineState.build) { $PipelineState.build } else { $null }
          route_discovery_result = $routeDiscoveryResult
          task = $task
          build_truth_gate = if ($PipelineState.post_build_decision -and $PipelineState.post_build_decision.build_truth_gate) { $PipelineState.post_build_decision.build_truth_gate } else { $null }

        next_step = $safeNextStep

        forbidden_steps = @(
            "add ZIP/REPO/PROMPT before self_build is verified",
            "add benchmark before evidence index exists",
            "add screenshots before output contract is stable",
            "claim PASS beyond current baseline evidence"
        )
    }

    if ($PipelineState.selection -and $PipelineState.selection.session_ledger_path) {
        $ledgerPath = [string]$PipelineState.selection.session_ledger_path
        if (Test-Path -LiteralPath $ledgerPath) {
            $ledger = Get-Content -Path $ledgerPath -Raw | ConvertFrom-Json -AsHashtable
            if (-not $ledger.ContainsKey("batch_history")) { $ledger.batch_history = @() }
            if (-not $ledger.ContainsKey("cumulative_findings")) { $ledger.cumulative_findings = @() }
            if (-not $ledger.ContainsKey("cumulative_finding_actions")) { $ledger.cumulative_finding_actions = @() }

            $batchUrls = @($PipelineState.selection.selected | ForEach-Object { [string]$_.url })
            foreach ($u in $batchUrls) {
                if ($ledger.audited_urls -notcontains $u) { $ledger.audited_urls += $u }
                $ledger.pending_urls = @($ledger.pending_urls | Where-Object { $_ -ne $u })
            }
            $batchOrdinal = @($ledger.completed_batch_ids).Count + 1
            $batchId = "batch-" + ([string]$batchOrdinal).PadLeft(3,'0')
            $ledger.completed_batch_ids += $batchId
            $ledger.last_completed_run_id = $runId
            if ($PipelineState.decision -and $PipelineState.decision.finding_counts) {
                foreach ($k in @("critical","high","medium","low")) {
                    $ledger.aggregate_findings[$k] = [int]$ledger.aggregate_findings[$k] + [int]$PipelineState.decision.finding_counts[$k]
                }
            }
            if ($PipelineState.reconcile -and $PipelineState.reconcile.findings) {
                foreach ($finding in @($PipelineState.reconcile.findings)) {
                    $ledger.cumulative_findings += $finding
                }
            }
            if ($PipelineState.reconcile -and $PipelineState.reconcile.finding_actions) {
                foreach ($findingAction in @($PipelineState.reconcile.finding_actions)) {
                    $ledger.cumulative_finding_actions += $findingAction
                }
            }
            if ([int]$ledger.inventory_url_count -gt 0) {
                $ledger.coverage_percent = [math]::Round((@($ledger.audited_urls).Count * 100.0) / [int]$ledger.inventory_url_count, 2)
            }
            $ledger.next_action = if (@($ledger.pending_urls).Count -eq 0) { "FINAL_SUMMARY" } elseif ($PipelineState.run.execution_status -eq "FAIL") { "STOP_NEEDS_REPAIR" } else { "NEXT_BATCH" }

            $batchHistoryEntry = [ordered]@{
                batch_id = $batchId
                run_id = $runId
                audit_action = if ($PipelineState.selection -and $PipelineState.selection.audit_action) { [string]$PipelineState.selection.audit_action } else { "UNKNOWN" }
                audited_count = $batchUrls.Count
                audited_urls = @($batchUrls)
                finding_counts = $findingCounts
                verdict = $verdict
                score = $score
            }
            $ledger.batch_history += $batchHistoryEntry
            $ledger | ConvertTo-Json -Depth 40 | Set-Content -Path $ledgerPath -Encoding UTF8

            $report.audit_session.total_audited_count = @($ledger.audited_urls).Count
            $report.audit_session.total_pending_count = @($ledger.pending_urls).Count
            $report.audit_session.coverage_percent = $ledger.coverage_percent
            $report.audit_session.next_action = [string]$ledger.next_action
            $report.audit_session.aggregate_findings = $ledger.aggregate_findings

            $sessionStatus = if (@($ledger.pending_urls).Count -eq 0) { "READY_FOR_FINAL" } else { "IN_PROGRESS" }
            $report.session_summary = [ordered]@{
                session_id = [string]$ledger.session_id
                target_url = if ($ledger.ContainsKey("target_url")) { [string]$ledger.target_url } else { $null }
                base_url = [string]$ledger.base_url
                batches_completed = @($ledger.completed_batch_ids).Count
                completed_batch_ids = @($ledger.completed_batch_ids)
                total_inventory_count = [int]$ledger.inventory_url_count
                total_audited_count = @($ledger.audited_urls).Count
                total_pending_count = @($ledger.pending_urls).Count
                coverage_percent = [double]$ledger.coverage_percent
                aggregate_findings = $ledger.aggregate_findings
                cumulative_findings_count = @($ledger.cumulative_findings).Count
                cumulative_finding_actions_count = @($ledger.cumulative_finding_actions).Count
                session_status = $sessionStatus
                next_action = [string]$ledger.next_action
            }
            $report.current_batch_summary = [ordered]@{
                batch_id = $batchId
                run_id = $runId
                audit_action = if ($PipelineState.selection -and $PipelineState.selection.audit_action) { [string]$PipelineState.selection.audit_action } else { "UNKNOWN" }
                audited_in_this_run = $batchUrls.Count
                findings_in_this_run = $findingCounts
                batch_verdict = $verdict
                batch_score = $score
                session_total_audited_after_run = @($ledger.audited_urls).Count
                session_total_pending_after_run = @($ledger.pending_urls).Count
                session_coverage_after_run = [double]$ledger.coverage_percent
            }
        }
    }

    $agentMap = New-SiteAuditorV3AgentMap -PipelineState $PipelineState -RunRoot $runRoot
    $agentMapJsonPath = Join-Path $runRoot "AGENT_MAP.json"
    $agentMapMdPath = Join-Path $runRoot "AGENT_MAP.md"

    $agentMap | ConvertTo-Json -Depth 20 | Set-Content -Path $agentMapJsonPath -Encoding UTF8
    Convert-SiteAuditorV3AgentMapToMarkdown -AgentMap $agentMap | Set-Content -Path $agentMapMdPath -Encoding UTF8

    $reportPath = Join-Path $runRoot "RUN_REPORT.json"
    $report | ConvertTo-Json -Depth 40 | Set-Content -Path $reportPath -Encoding UTF8

    $taskPath = $null
    if ($task) {
        $taskPath = Join-Path $runRoot "TASK.json"
        $task | ConvertTo-Json -Depth 20 | Set-Content -Path $taskPath -Encoding UTF8
    }

    return @{ status = "OK"; data = @{ runpack_root = $runRoot; run_report = $reportPath; task = $taskPath; agent_map_json = $agentMapJsonPath; agent_map_md = $agentMapMdPath } }
}
