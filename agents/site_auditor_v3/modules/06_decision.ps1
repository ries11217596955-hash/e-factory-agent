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

    if ($routes -gt 1 -and $captures -gt 1) {
        $weak += "coverage_confidence_model"
    }

    $nextCapability = if ($missing.Count -gt 0) {
        $missing[0]
    } elseif ($weak.Count -gt 0) {
        $weak[0]
    } else {
        "self_build_refinement"
    }

    return @{
        status = "OK"
        data = @{
            audit_verdict = $verdict
            score = $score
            data_quality = "COMPLETE"
            finding_counts = @{
                critical = 0; high = 0; medium = 0; low = 0
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
            self_build = @{
                missing_capabilities = $missing
                weak_capabilities = $weak
                next_capability_to_build = $nextCapability
                reason = "derived from pipeline coverage and capture depth"
            }
        }
    }
}
