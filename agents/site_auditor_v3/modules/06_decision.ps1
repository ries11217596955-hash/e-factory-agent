function Invoke-Module06Decision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $routesDiscovered  = [int]$PipelineState.route_audit.totals.discovered
    $routesSelected    = [int]$PipelineState.selection.totals.selected
    $capturesSucceeded = [int]$PipelineState.capture.totals.succeeded
    $gaps              = @($PipelineState.reconcile.gaps)

    # === BASELINE DETECTION ===
    $isBaseline = ($routesDiscovered -le 1 -or $capturesSucceeded -le 1)

    # === DEFAULT DECISION ===
    $verdict = "PASS"
    $score   = 100

    if ($isBaseline) {
        $verdict = "INCONCLUSIVE"
        $score   = 30
    }

    # === DIAGNOSTIC ===
    $diagnostic = @{
        failed_stage = $null
        what_worked = @("input","route_audit","selection","capture","reconcile")
        what_failed = @()
        limitations = @()
        evidence_gaps = @()
        confidence = "LOW"
        next_debug_step = "Expand routes and capture depth before strong decision"
        next_build_step = "Add self_build capability posture to 06_decision"
        forbidden_next_steps = @(
            "do not add ZIP/REPO/PROMPT modes before self_build exists",
            "do not claim strong PASS without evidence coverage",
            "do not add new modules without RUN_REPORT next_step alignment"
        )
    }

    if ($isBaseline) {
        $diagnostic.limitations += "baseline_coverage_only"
        $diagnostic.evidence_gaps += "insufficient_routes_and_captures"
    }

    # === SELF BUILD ===
    $missing = @()
    $weak = @()

    if ($routesDiscovered -le 1) {
        $missing += "route_depth_expansion"
    }

    if ($capturesSucceeded -le 1) {
        $missing += "evidence_quality_classification"
        $missing += "suspiciously_clean_detection"
    }

    if ($gaps.Count -eq 0 -and $routesDiscovered -le 1) {
        $weak += "coverage_confidence_model"
    }

    $nextCapability = if ($missing.Count -gt 0) { $missing[0] } else { "self_build_refinement" }

    $selfBuild = @{
        missing_capabilities = $missing
        weak_capabilities = $weak
        next_capability_to_build = $nextCapability
        reason = "derived from low route count and minimal capture coverage"
    }

    return @{
        status = "OK"
        data = @{
            audit_verdict = $verdict
            score = $score
            data_quality = "PARTIAL"
            finding_counts = @{
                critical = 0; high = 0; medium = 0; low = 0
            }
            self_diagnostic = $diagnostic
            self_build = $selfBuild
        }
    }
}
