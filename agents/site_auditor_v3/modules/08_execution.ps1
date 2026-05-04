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
        "proceed_next_layer" = @{
            command_id = "READ_NEXT_CAPABILITY"
            command = "read_latest_run_report"
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

    $plan = $allowlist[$actionId].Clone()
    $plan.action_id = $actionId
    $plan.source_action = $action.action
    $plan.safety = @{
        shell_execution = $false
        file_write = $false
        git_write = $false
        network = $false
    }

    return @{
        status = "OK"
        data = @{
            execution_plan = $plan
        }
    }
}
