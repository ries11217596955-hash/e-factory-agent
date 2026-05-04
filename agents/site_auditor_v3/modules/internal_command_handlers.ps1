function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    if ($Command.handler -eq "prepare_capability_task") {
        $targetCapability = [string]$PipelineState.decision.self_build.next_capability_to_build

        $detectedGaps = @()

        if ($PipelineState.decision.self_diagnostic.limitations) {
            foreach ($x in @($PipelineState.decision.self_diagnostic.limitations)) {
                $detectedGaps += @{
                    source = "decision.self_diagnostic.limitations"
                    type = "limitation"
                    value = [string]$x
                }
            }
        }

        if ($PipelineState.reconcile -and $PipelineState.reconcile.gaps) {
            foreach ($x in @($PipelineState.reconcile.gaps)) {
                $detectedGaps += @{
                    source = "reconcile.gaps"
                    type = "coverage_gap"
                    value = $x
                }
            }
        }

        $routesDiscovered = if ($PipelineState.route_audit -and $PipelineState.route_audit.totals) { [int]$PipelineState.route_audit.totals.discovered } else { 0 }
        $capturesSucceeded = if ($PipelineState.capture -and $PipelineState.capture.totals) { [int]$PipelineState.capture.totals.succeeded } else { 0 }

        if ($routesDiscovered -gt 0 -and $capturesSucceeded -lt $routesDiscovered) {
            $detectedGaps += @{
                source = "route_audit_vs_capture"
                type = "incomplete_capture_coverage"
                routes_discovered = $routesDiscovered
                captures_succeeded = $capturesSucceeded
            }
        }

        if ($PipelineState.visual_capture -and $PipelineState.visual_capture.totals) {
            $visualRequested = if ($null -ne $PipelineState.visual_capture.totals.requested) { [int]$PipelineState.visual_capture.totals.requested } else { 0 }
            $visualSucceeded = if ($null -ne $PipelineState.visual_capture.totals.succeeded) { [int]$PipelineState.visual_capture.totals.succeeded } else { 0 }

            if ($visualRequested -gt 0 -and $visualSucceeded -lt $visualRequested) {
                $detectedGaps += @{
                    source = "visual_capture.totals"
                    type = "incomplete_visual_capture"
                    visual_requested = $visualRequested
                    visual_succeeded = $visualSucceeded
                }
            }
        }

        if ($targetCapability -eq "capability_discovery" -and @($detectedGaps).Count -eq 0) {
            $detectedGaps += @{
                source = "capability_discovery"
                type = "no_actionable_gap_detected"
                value = "self-build has no evidence gap to convert into a new capability"
            }
        }

        $task = @{
            capability_id = $targetCapability
            task_type = "BUILD_CAPABILITY"
            input = @{
                missing_capabilities = $PipelineState.decision.self_build.missing_capabilities
                weak_capabilities = $PipelineState.decision.self_build.weak_capabilities
                evidence_gaps = $detectedGaps
            }
            expected_output = @{
                state_key = $targetCapability
                validation = "state_key must appear in PipelineState"
            }
            constraints = @{
                forbidden = @(
                    "do not modify selector",
                    "do not modify completion engine",
                    "do not break pipeline order"
                )
            }
            diagnostic = @{
                reason = $PipelineState.decision.self_build.reason
                next_debug_step = $PipelineState.decision.self_diagnostic.next_debug_step
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
