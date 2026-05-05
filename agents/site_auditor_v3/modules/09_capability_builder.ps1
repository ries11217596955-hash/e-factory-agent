function Invoke-Module09CapabilityBuilder {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $task = $null

    # === SAFE TASK RESOLUTION ===
    if ($PipelineState.execution -and $PipelineState.execution.execution_result) {
        $handlerPath = (Resolve-Path "agents/site_auditor_v3/modules/internal_command_handlers.ps1").Path
        . $handlerPath

        $taskResult = Invoke-InternalCommand -Command @{ type="internal"; handler="prepare_capability_task"; args=@{} } -PipelineState $PipelineState
        if ($taskResult -and $taskResult.status -eq "OK") {
            $task = $taskResult.data.result
        }
    }

    if (-not $task -or $task.task_type -ne "BUILD_CAPABILITY") {
        return @{ status="OK"; data=@{ build_status="SKIPPED" } }
    }

    $capId = [string]$task.capability_id

    return @{
        status = "OK"
        data = @{
            build_status = "GENERATED"
            capability_id = $capId
            mode = "DRY_BUILD"
            note = "builder executed correctly"
        }
    }
}
