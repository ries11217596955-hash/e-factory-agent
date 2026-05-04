function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    if ($Command.handler -eq "prepare_capability_task") {

        $selectedCapability = [string]$PipelineState.decision.self_build.next_capability_to_build
        $targetCapability = $selectedCapability

        $detectedGaps = @()
        $candidates = @()

        # === COLLECT GAPS ===
        if ($PipelineState.decision.self_diagnostic.limitations) {
            foreach ($x in @($PipelineState.decision.self_diagnostic.limitations)) {
                $detectedGaps += @{
                    source = "decision.self_diagnostic.limitations"
                    type = "limitation"
                    value = [string]$x
                }
            }
        }

        $routesDiscovered = if ($PipelineState.route_audit) { [int]$PipelineState.route_audit.totals.discovered } else { 0 }

        if ($routesDiscovered -le 1) {
            $detectedGaps += @{
                type = "baseline_route_coverage_only"
                routes_discovered = $routesDiscovered
            }
            $candidates += "route_discovery"
        }

        if ($PipelineState.visual_capture) {
            $vr = [int]$PipelineState.visual_capture.totals.requested
            $vs = [int]$PipelineState.visual_capture.totals.succeeded

            if ($vr -gt 0 -and $vs -lt $vr) {
                $detectedGaps += @{
                    type = "incomplete_visual_capture"
                }
                $candidates += "visual_capture_fix"
            }
        }

        if ($PipelineState.reconcile -and $PipelineState.reconcile.findings) {
            $hasCTA = @($PipelineState.reconcile.findings | Where-Object { $_.code -eq "NO_CTA_SIGNAL" }).Count -gt 0
            if ($hasCTA) {
                $candidates += "conversion_signal_detection"
            }
        }

        # === RANKING ===
        $priority = @(
            "route_discovery",
            "capture_reliability",
            "visual_capture_fix",
            "conversion_signal_detection"
        )

        $selected = $null
        foreach ($p in $priority) {
            if ($candidates -contains $p) {
                $selected = $p
                break
            }
        }

        if ($selectedCapability -eq "capability_discovery" -and $selected) {
            $targetCapability = $selected
        }

        if (-not $selected) {
            $targetCapability = "capability_discovery"
        }

        $task = @{
            capability_id = $targetCapability
            discovered_from = $selectedCapability
            task_type = "BUILD_CAPABILITY"

            input = @{
                evidence_gaps = $detectedGaps
                candidates = $candidates
                selected = $selected
            }

            expected_output = @{
                state_key = $targetCapability
            }

            diagnostic = @{
                reason = "ranking-based selection"
                candidates = $candidates
                selected = $selected
            }
        }

        return @{
            status = "OK"
            data = @{
                result = $task
            }
        }
    }

    return @{
        status = "UNKNOWN_COMMAND"
        data = @{}
    }
}
