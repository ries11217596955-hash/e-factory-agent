function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    $handler = [string]$Command.handler

    if ($handler -eq "read_latest_run_report") {
    
    if ($handler -eq "prepare_capability_task") {
        $targetCapability = [string]$PipelineState.decision.self_build.next_capability_to_build
        $actionId = if ($PipelineState.decision.decision_action) { [string]$PipelineState.decision.decision_action.action_id } else { "unknown" }

        return @{
            status = "OK"
            data = @{
                handler = $handler
                result = @{
                    task_type = "capability_build"
                    target_capability = $targetCapability
                    source_action_id = $actionId
                    mode = "HUMAN_REVIEW"
                    objective = "Build the next capability selected by self_build."
                    validation = "./agents/site_auditor_v3/tests/run_suite.sh"
                    fail_mode = "Do not commit. Return RUN_REPORT and failing validator output."
                }
            }
        }
    }

    return @{
            status = "OK"
            data = @{
                handler = $handler
                result = @{
                    next_capability = $PipelineState.decision.self_build.next_capability_to_build
                    verdict = $PipelineState.decision.audit_verdict
                    score = $PipelineState.decision.score
                }
            }
        }
    }


    if ($handler -eq "prepare_capability_task") {
        $targetCapability = [string]$PipelineState.decision.self_build.next_capability_to_build
        $actionId = if ($PipelineState.decision.decision_action) { [string]$PipelineState.decision.decision_action.action_id } else { "unknown" }

        return @{
            status = "OK"
            data = @{
                handler = $handler
                result = @{
                    task_type = "capability_build"
                    target_capability = $targetCapability
                    source_action_id = $actionId
                    mode = "HUMAN_REVIEW"
                    objective = "Build the next capability selected by self_build."
                    validation = "./agents/site_auditor_v3/tests/run_suite.sh"
                    fail_mode = "Do not commit. Return RUN_REPORT and failing validator output."
                }
            }
        }
    }

    return @{
        status = "BLOCKED"
        data = @{
            handler = $handler
            reason = "handler_not_allowlisted"
        }
    }
}
