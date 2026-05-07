function New-SiteAuditorV3DecisionNextStepBlock {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$FallbackDecisionAction
    )

    $safeDecisionAction = if ($PipelineState.post_build_decision -and $PipelineState.post_build_decision.decision_action) {
        $PipelineState.post_build_decision.decision_action
    } elseif ($PipelineState.decision -and $PipelineState.decision.decision_action) {
        $PipelineState.decision.decision_action
    } else {
        $FallbackDecisionAction
    }

    $safeNextStep = if ($PipelineState.post_build_decision -and $PipelineState.post_build_decision.decision_action) {
        $PipelineState.post_build_decision.decision_action
    } elseif ($PipelineState.build -and $PipelineState.build.next_action) {
        $PipelineState.build.next_action
    } elseif ($PipelineState.decision -and $PipelineState.decision.decision_action) {
        $PipelineState.decision.decision_action
    } else {
        $FallbackDecisionAction
    }

    return [ordered]@{
        decision_action = $safeDecisionAction
        next_step = $safeNextStep
    }
}
