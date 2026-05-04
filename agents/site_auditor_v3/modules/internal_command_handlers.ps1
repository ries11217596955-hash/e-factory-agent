function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    $handler = [string]$Command.handler

    if ($handler -eq "read_latest_run_report") {
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

    return @{
        status = "BLOCKED"
        data = @{
            handler = $handler
            reason = "handler_not_allowlisted"
        }
    }
}
