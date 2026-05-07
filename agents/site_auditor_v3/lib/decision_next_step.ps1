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

    $actionText = if ($safeDecisionAction -and $safeDecisionAction.action) {
        [string]$safeDecisionAction.action
    } else {
        "inspect RUN_REPORT decision_action"
    }

    $targetModule = if ($safeDecisionAction -and $safeDecisionAction.target_module) {
        [string]$safeDecisionAction.target_module
    } else {
        "unknown"
    }

    $why = if ($safeDecisionAction -and $safeDecisionAction.why) {
        [string]$safeDecisionAction.why
    } else {
        "decision_action selected this as the next executable action"
    }

    $safeNextStep = [ordered]@{
        action = $actionText
        instruction = ("{0}. Owner module: {1}. Verify evidence before closing." -f $actionText, $targetModule)
        target_module = $targetModule
        why = $why
    }

    return [ordered]@{
        decision_action = $safeDecisionAction
        next_step = $safeNextStep
    }
}
