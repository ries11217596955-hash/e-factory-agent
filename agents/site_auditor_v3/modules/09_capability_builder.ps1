function Invoke-Module09CapabilityBuilder {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $handlerPath = (Resolve-Path "agents/site_auditor_v3/modules/internal_command_handlers.ps1").Path
    . $handlerPath

    $taskResult = Invoke-InternalCommand -Command @{ type="internal"; handler="prepare_capability_task"; args=@{} } -PipelineState $PipelineState
    $task = if ($taskResult -and $taskResult.status -eq "OK") { $taskResult.data.result } else { $null }

    if (-not $task -or $task.task_type -ne "BUILD_CAPABILITY") {
        return @{
            status = "OK"
            data = @{
                build_status = "SKIPPED"
                next_action = @{
                    action_id = "none"
                    action = "none"
                    why = "no build task"
                    source = "builder"
                }
            }
        }
    }

    $capId = [string]$task.capability_id

    return @{
        status = "OK"
        data = @{
            build_status = "GENERATED"
            capability_id = $capId
            mode = "DRY_BUILD"
            note = "builder executed correctly"
            next_action = @{
                action_id = "integrate_generated_capability"
                action = "integrate generated capability"
                why = "capability_builder generated a build artifact that is not yet integrated"
                source = "build_state"
                priority = "highest"
                target_module = "capability_integration"
            }
        }
    }
}
