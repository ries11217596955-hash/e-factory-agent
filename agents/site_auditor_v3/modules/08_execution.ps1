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
                execution_plan = @{
                    mode = "BLOCKED"
                    status = "NO_ACTION"
                    reason = "no_decision_action"
                }
            }
        }
    }

    $allowlist = @{
        "prepare_next_capability_task" = @{
            command_id = "PREPARE_CAPABILITY_TASK"
            command = @{
                type = "internal"
                handler = "prepare_capability_task"
                args = @{}
            }
            mode = "SAFE_EXECUTE"
            status = "READY"
            target = "RUN_REPORT.agent_capability_state.next_capability_to_build"
        }
        "expand_routes" = @{
            command_id = "BUILD_ROUTE_DEPTH_EXPANSION"
            command = "prepare_capability_task"
            mode = "DRY_RUN"
            status = "READY"
            target = "route_audit"
        }
        "improve_capture" = @{
            command_id = "BUILD_CAPTURE_EXPANSION"
            command = "prepare_capability_task"
            mode = "DRY_RUN"
            status = "READY"
            target = "capture"
        }
        "fix_findings" = @{
            command_id = "BUILD_FINDINGS_ACTION_MAPPING"
            command = "prepare_capability_task"
            mode = "DRY_RUN"
            status = "READY"
            target = "reconcile"
        }
    }

    $actionId = [string]$action.action_id

    if (-not $allowlist.ContainsKey($actionId)) {
        return @{
            status = "BLOCKED"
            data = @{
                execution_plan = @{
                    action_id = $actionId
                    mode = "BLOCKED"
                    status = "NOT_ALLOWLISTED"
                    reason = "action_id_not_allowlisted"
                }
            }
        }
    }

    . "agents/site_auditor_v3/modules/internal_command_handlers.ps1"

    $plan = $allowlist[$actionId].Clone()
    $plan.action_id = $actionId
    $plan.source_action = $action.action
    $plan.safety = @{
        shell_execution = $false
        file_write = $false
        git_write = $false
        network = $false
    }

    $executionResult = $null
    if ($plan.mode -eq "SAFE_EXECUTE" -and $plan.command.type -eq "internal") {
        $executionResult = Invoke-InternalCommand -Command $plan.command -PipelineState $PipelineState
    }

    return @{
        status = "OK"
        data = @{
            execution_plan = $plan
            execution_result = $executionResult
        }
    }
}
