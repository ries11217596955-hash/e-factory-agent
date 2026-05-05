function Invoke-Module10PostBuildDecision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $baseDecision = $PipelineState.decision
    $build = $PipelineState.build

    if ($build -and $build.build_status -eq "GENERATED" -and $build.next_action) {
        return @{
            status = "OK"
            data = @{
                decision_action = $build.next_action
                source = "post_build_decision"
                reason = "build generated next action"
            }
        }
    }

    return @{
        status = "OK"
        data = @{
            decision_action = $baseDecision.decision_action
            source = "base_decision"
            reason = "no build override"
        }
    }
}
