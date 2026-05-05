function Invoke-Module06Decision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $routes = if ($PipelineState.route_audit) { [int]$PipelineState.route_audit.totals.discovered } else { 0 }
    $captures = if ($PipelineState.capture) { [int]$PipelineState.capture.totals.succeeded } else { 0 }

    $verdict = "PASS"
    $score = 100
    $limitations = @()

    if ($routes -le 1 -or $captures -le 1) {
        $verdict = "INCONCLUSIVE"
        $score = 30
        $limitations += "baseline_coverage_only"
    }

    # === SELF BUILD / UNIVERSAL COMPLETION ENGINE ===
    $completedCapabilities = @(
        "coverage_confidence_model",
        "decision_action_mapping",
        "execution_layer_bootstrap",
        "capability_task_output"
    )

    $auditorCapabilityQueue = @(
        @{ id = "route_depth_expansion"; state = "route_audit" }
        @{ id = "capture_expansion"; state = "capture" }
        @{ id = "findings_action_mapping"; state = "reconcile" }
        @{ id = "visual_capture"; state = "visual_capture" }
    )

    $autoCompleted = @()
    foreach ($cap in $auditorCapabilityQueue) {
        if ($PipelineState.ContainsKey($cap.state)) {
            $autoCompleted += $cap.id
        }
    }

    $completedCapabilities = @($completedCapabilities + $autoCompleted | Select-Object -Unique)

    $missing = @()
    $weak = @()

    if ($routes -le 1) {
        $missing += "route_depth_expansion"
    }

    if ($captures -le 1) {
        $missing += "capture_expansion"
    }

    # === COVERAGE CONFIDENCE MODEL (RECONCILE-BOUND) ===
    $coverageData = if ($PipelineState.reconcile) { $PipelineState.reconcile.coverage } else { @() }

    $totalRoutes = @($coverageData).Count
    $fullCovered = @($coverageData | Where-Object { $_.coverage_status -eq "FULL" }).Count
    $missingCovered = @($coverageData | Where-Object { $_.coverage_status -eq "NONE" }).Count

    $coverageConfidence = "LOW"

    if ($totalRoutes -gt 0) {
        $coverageRatio = $fullCovered / $totalRoutes

        if ($coverageRatio -ge 0.8 -and $missingCovered -eq 0) {
            $coverageConfidence = "HIGH"
        }
        elseif ($coverageRatio -ge 0.5) {
            $coverageConfidence = "MEDIUM"
        }
    }

    if ($coverageConfidence -eq "LOW") {
        $verdict = "INCONCLUSIVE"
        $score = 40
        if (-not ($limitations -contains "low_coverage_confidence")) {
            $limitations += "low_coverage_confidence"
        }
    }

    if ($missingCovered -gt 0) {
        if (-not ($limitations -contains "coverage_gaps_present")) {
            $limitations += "coverage_gaps_present"
        }
    }

    if ($coverageConfidence -ne "HIGH") {
        if (-not ($weak -contains "coverage_confidence_model")) {
            $weak += "coverage_confidence_model"
        }
    }

    $missing = @($missing | Where-Object { -not ($completedCapabilities -contains $_) })
    $weak = @($weak | Where-Object { -not ($completedCapabilities -contains $_) })

    $nextCapability = if ($missing.Count -gt 0) {
        $missing[0]
    } elseif ($weak.Count -gt 0) {
        $weak[0]
    } else {
        $(if (@($auditorCapabilityQueue | Where-Object { -not ($completedCapabilities -contains $_.id) }).Count -gt 0) { @($auditorCapabilityQueue | Where-Object { -not ($completedCapabilities -contains $_.id) })[0].id } else { "capability_discovery" })
    }

    # === DECISION EVIDENCE BINDING ===
    $evidenceQuality = if ($PipelineState.reconcile -and $PipelineState.reconcile.evidence_quality) {
        $PipelineState.reconcile.evidence_quality.status
    } else {
        "UNKNOWN"
    }

    $decisionReason = @()

    if ($routes -le 1) {
        $decisionReason += "insufficient_route_coverage"
    }

    if ($captures -le 1) {
        $decisionReason += "insufficient_capture_coverage"
    }

    if ($evidenceQuality -eq "WEAK") {
        $decisionReason += "low_evidence_quality"
    }

    if ($decisionReason.Count -eq 0) {
        $decisionReason += "sufficient_coverage_and_quality"
    }

    # === DECISION ACTION MAPPING ===
    $hasFindings = $false
    if ($PipelineState.reconcile -and $PipelineState.reconcile.findings) {
        $hasFindings = @($PipelineState.reconcile.findings).Count -gt 0
    }

    $decisionAction = @{
        action_id = "unknown"
        priority = "normal"
        action = "none"
        why = "no_mapping"
        target_module = "none"
        next_command_hint = "none"
    }

    if ($verdict -eq "INCONCLUSIVE" -and ($limitations -contains "baseline_coverage_only")) {
        $decisionAction = @{
            action_id = "expand_routes"
            priority = "high"
            action = "run route_depth_expansion"
            why = "insufficient_route_coverage"
            target_module = "route_audit"
            next_command_hint = "build route_depth_expansion capability"
        }
    }
    elseif ($verdict -eq "INCONCLUSIVE" -and ($limitations -contains "low_coverage_confidence")) {
        $decisionAction = @{
            action_id = "improve_capture"
            priority = "high"
            action = "run capture_expansion"
            why = "low_coverage_confidence"
            target_module = "capture"
            next_command_hint = "build capture_expansion capability"
        }
    }
    elseif ($hasFindings) {
        $decisionAction = @{
            action_id = "fix_findings"
            priority = "medium"
            action = "analyze and resolve findings"
            why = "findings_present"
            target_module = "reconcile"
            next_command_hint = "build findings_action_mapping"
        }
    }
    elseif ($verdict -eq "PASS") {
        $decisionAction = @{
            action_id = "prepare_next_capability_task"
            priority = "low"
            action = "advance to next capability layer"
            why = "clean_pass"
            target_module = "meta"
            next_command_hint = "build next selected capability"
        }
    }

    
    # === BUILD STATE OVERRIDE ===
    if ($PipelineState.build -and $PipelineState.build.build_status -eq "GENERATED") {
        $decisionAction = @{
            action_id = "integrate_generated_capability"
            action = "integrate generated capability"
            why = "build artifact exists but is not integrated"
            target_module = "capability_integration"
            priority = "highest"
        }
    }

return @{
        status = "OK"
        data = @{
            audit_verdict = $verdict
            score = $score
            data_quality = "COMPLETE"
            finding_counts = @{
                critical = @($PipelineState.reconcile.findings | Where-Object { $_.type -eq "critical" }).Count
                high = @($PipelineState.reconcile.findings | Where-Object { $_.type -eq "high" }).Count
                medium = @($PipelineState.reconcile.findings | Where-Object { $_.type -eq "medium" }).Count
                low = @($PipelineState.reconcile.findings | Where-Object { $_.type -eq "low" }).Count
            }
            self_diagnostic = @{
                failed_stage = $null
                what_worked = @("input","route_audit","selection","capture","visual_capture","reconcile")
                what_failed = @()
                limitations = $limitations
                evidence_gaps = @()
                confidence = if ($verdict -eq "PASS") { "HIGH" } else { "LOW" }
                next_debug_step = "Read RUN_REPORT, evidence_summary, and TASK.json"
                next_build_step = $nextCapability
                forbidden_next_steps = @(
                    "do not claim PASS without sufficient coverage",
                    "do not skip route expansion",
                    "do not invent findings"
                )
            }
            decision_reason = $decisionReason
            decision_action = $decisionAction
            self_build = @{
                missing_capabilities = $missing
                weak_capabilities = $weak
                completed_capabilities = $completedCapabilities
                auditor_capability_queue = $auditorCapabilityQueue
                next_capability_to_build = $nextCapability
                reason = "derived from pipeline state, capability queue, and completed capability evidence"
            }
        }
    }
}
