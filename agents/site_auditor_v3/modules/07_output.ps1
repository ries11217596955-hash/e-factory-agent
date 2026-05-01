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
        if ($PipelineState.ContainsKey($key)) {
            $pipelineStatus[$key] = "OK"
        } else {
            $pipelineStatus[$key] = "SKIPPED"
        }
    }

    $report = [ordered]@{
        read_me_first = $true

        identity = [ordered]@{
            agent = "SITE_AUDITOR_V3"
            mode = "BUILD"
            run_id = $runId
            current_stage = "RUN_REPORT_V1"
        }

        mission = [ordered]@{
            goal = "input -> weak points -> evidence -> decision -> action -> next capability"
            forbidden = @(
                "silent fail",
                "fake PASS",
                "decision without evidence",
                "output inventing findings"
            )
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
            verdict = $PipelineState.decision.audit_verdict
            score = $PipelineState.decision.score
            data_quality = $PipelineState.decision.data_quality
            finding_counts = $PipelineState.decision.finding_counts
        }

        evidence_summary = [ordered]@{
            routes_discovered = $PipelineState.route_audit.totals.discovered
            routes_selected = $PipelineState.selection.totals.selected
            captures_requested = $PipelineState.capture.totals.requested
            captures_succeeded = $PipelineState.capture.totals.succeeded
            coverage_status = $PipelineState.reconcile.status
            gaps_count = @($PipelineState.reconcile.gaps).Count
        }

        diagnostic_summary = [ordered]@{
            status = $PipelineState.run.execution_status
            failed_stage = $null
            limitations = @()
        }

        agent_capability_state = [ordered]@{
            source = "agents/site_auditor_v3/docs/CAPABILITY_MAP.md"
            next_capability_to_build = "RUN_REPORT as operator re-entry file"
        }

        next_step = [ordered]@{
            action = "Verify RUN_REPORT.json content and commit 07_output v1"
            why = "RUN_REPORT must become the first readable artifact before deeper audit capabilities are added."
            expected_result = "Future chats can restart from RUN_REPORT.json without guessing."
        }

        forbidden_steps = @(
            "add ZIP/REPO/PROMPT before RUN_REPORT is verified",
            "add benchmark before evidence index exists",
            "add screenshots before output contract is stable",
            "claim PASS beyond current stub evidence"
        )
    }

    $reportPath = Join-Path $runRoot "RUN_REPORT.json"
    $report | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath -Encoding UTF8

    return @{
        status = "OK"
        data = @{
            runpack_root = $runRoot
            run_report = $reportPath
        }
    }
}
