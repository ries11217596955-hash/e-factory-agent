function Invoke-Module08Execution {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $action = $PipelineState.decision.decision_action

    if (-not $action) {
        return @{
            status = "SKIPPED"
            data = @{
                reason = "no_decision_action"
            }
        }
    }

    # === EXECUTION STUB (SAFE MODE) ===
    # We DO NOT execute real actions yet.
    # We only prepare execution plan.

    $executionPlan = @{
        action_id = $action.action_id
        target_module = $action.target_module
        command_hint = $action.next_command_hint
        mode = "DRY_RUN"
        status = "READY"
    }

    return @{
        status = "OK"
        data = @{
            execution_plan = $executionPlan
        }
    }
}
