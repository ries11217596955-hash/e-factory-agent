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

    # === SELF BUILD REAL LOGIC ===
    $missing = @()
    $weak = @()

    if ($routes -le 1) {
        $missing += "route_depth_expansion"
    }

    if ($captures -le 1) {
        $missing += "capture_expansion"
    }

    # coverage_confidence_model is evaluated after reconcile-bound confidence is computed.
    # Do not mark it weak upfront just because routes/captures are above baseline.

    $nextCapability = if ($missing.Count -gt 0) {
        $missing[0]
    } elseif ($weak.Count -gt 0) {
        $weak[0]
    } else {
        "self_build_refinement"
    }

    
    # === COVERAGE CONFIDENCE MODEL (RECONCILE-BOUND) ===

    $coverageData = if ($PipelineState.reconcile) { $PipelineState.reconcile.coverage } else { @() }
    $gapsData = if ($PipelineState.reconcile) { $PipelineState.reconcile.gaps } else { @() }

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

    
    # === DECISION EVIDENCE BINDING ===
    $evidenceQuality = if ($PipelineState.reconcile -and $PipelineState.reconcile.evidence_quality) {
        $PipelineState.reconcile.evidence_quality.status
    } else {
        "UNKNOWN"
    }

    $nextCapability = if ($missing.Count -gt 0) {
        $missing[0]
    } elseif ($weak.Count -gt 0) {
        $weak[0]
    } else {
        "self_build_refinement"
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
                what_worked = @("input","route_audit","selection","capture","reconcile")
                what_failed = @()
                limitations = $limitations
                evidence_gaps = @()
                confidence = if ($verdict -eq "PASS") { "HIGH" } else { "LOW" }
                next_debug_step = "Expand routes/capture if inconclusive"
                next_build_step = "Improve self_build decision logic"
                forbidden_next_steps = @(
                    "do not claim PASS without sufficient coverage",
                    "do not skip route expansion",
                    "do not invent findings"
                )
            }
            decision_reason = $decisionReason
            self_build = @{
                missing_capabilities = $missing
                weak_capabilities = $weak
                next_capability_to_build = $nextCapability
                reason = "derived from pipeline coverage and capture depth"
            }
        }
    }
}
