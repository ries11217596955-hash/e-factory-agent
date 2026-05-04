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

        identity = [ordered]@{
            agent = "SITE_AUDITOR_V3"
            mode = "BUILD"
            run_id = $runId
            current_stage = "RUN_REPORT_REENTRY_V1"
        }

        mission = [ordered]@{
            goal = "input -> weak points -> evidence -> decision -> action -> next capability"
            forbidden = @("silent fail","fake PASS","decision without evidence","output inventing findings")
        }

        operator_instruction = [ordered]@{
            for_chatgpt = "Read this RUN_REPORT.json first. Do not guess. Use read_order and if_problem_then_read. Choose one bottleneck and one next step."
            for_agent = "Return a usable result or a diagnostic. Declare missing capability instead of pretending."
            for_owner = "This file explains what happened, what to read, and what to do next."
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
            captures_requested = if ($PipelineState.capture) { $PipelineState.capture.totals.requested } else { 0 }
            captures_succeeded = if ($PipelineState.capture) { $PipelineState.capture.totals.succeeded } else { 0 }
            coverage_status = if ($PipelineState.reconcile) { $PipelineState.reconcile.status } else { "NOT_RUN" }
            gaps_count = if ($PipelineState.reconcile) { @($PipelineState.reconcile.gaps).Count } else { 0 }
            evidence_quality = $evidenceQuality
            findings = if ($PipelineState.reconcile -and $PipelineState.reconcile.findings) { $PipelineState.reconcile.findings } else { @() }
        }

        diagnostic_summary = $diag
        agent_capability_state = $cap

        decision_action = $PipelineState.decision.decision_action
        execution = if ($PipelineState.execution) { $PipelineState.execution } else { $null }

        next_step = [ordered]@{
            action = $PipelineState.decision.decision_action.action
            why = $cap.reason
            expected_result = "Agent selects the next build capability from evidence and diagnostic state."
        }

        forbidden_steps = @(
            "add ZIP/REPO/PROMPT before self_build is verified",
            "add benchmark before evidence index exists",
            "add screenshots before output contract is stable",
            "claim PASS beyond current baseline evidence"
        )
    }

    $reportPath = Join-Path $runRoot "RUN_REPORT.json"
    $report | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath -Encoding UTF8

    $task = if ($PipelineState.execution -and $PipelineState.execution.execution_result -and $PipelineState.execution.execution_result.data) {
        $PipelineState.execution.execution_result.data.result
    } else {
        $null
    }

    $taskPath = $null
    if ($task) {
        $taskPath = Join-Path $runRoot "TASK.json"
        $task | ConvertTo-Json -Depth 20 | Set-Content -Path $taskPath -Encoding UTF8
    }

    return @{ status = "OK"; data = @{ runpack_root = $runRoot; run_report = $reportPath; task = $taskPath } }
}
