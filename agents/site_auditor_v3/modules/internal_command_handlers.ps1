function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    if ($Command.handler -eq "prepare_capability_task") {

        $targetCapability = [string]$PipelineState.decision.self_build.next_capability_to_build

        $gaps = @()
        if ($PipelineState.decision.self_diagnostic.limitations) {
            $gaps += $PipelineState.decision.self_diagnostic.limitations
        }

        if ($PipelineState.reconcile -and $PipelineState.reconcile.gaps) {
            $gaps += $PipelineState.reconcile.gaps
        }

        $task = @{
            capability_id = $targetCapability
            task_type = "BUILD_CAPABILITY"

            input = @{
                missing_capabilities = $PipelineState.decision.self_build.missing_capabilities
                weak_capabilities = $PipelineState.decision.self_build.weak_capabilities
                evidence_gaps = $gaps
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
