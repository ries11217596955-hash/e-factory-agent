function New-SiteAuditorV3DecisionNextStepBlock {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$FallbackDecisionAction
    )

    $sessionAction = if ($PipelineState.selection -and $PipelineState.selection.audit_action) {
        [string]$PipelineState.selection.audit_action
    } else {
        $null
    }

    $sessionId = if ($PipelineState.selection -and $PipelineState.selection.session_id) {
        [string]$PipelineState.selection.session_id
    } else {
        $null
    }

    $nextPendingCount = if ($PipelineState.selection -and $null -ne $PipelineState.selection.next_pending_count) {
        [int]$PipelineState.selection.next_pending_count
    } else {
        0
    }

    $sessionContinuationRequired = (
        $sessionId -and
        $sessionAction -in @("START", "NEXT") -and
        $nextPendingCount -gt 0
    )

    $safeDecisionAction = if ($sessionContinuationRequired) {
        [ordered]@{
            action_id = "continue_audit_session"
            action = "continue current audit session with the next batch"
            why = "pending_routes_remaining"
            target_module = "audit_session"
            priority = "highest"
            next_command_hint = ("run audit_action=NEXT with session_id={0}" -f $sessionId)
            session_id = $sessionId
            pending_count = $nextPendingCount
        }
    } elseif ($PipelineState.post_build_decision -and $PipelineState.post_build_decision.decision_action) {
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

    $actionId = if ($safeDecisionAction -and $safeDecisionAction.action_id) {
        [string]$safeDecisionAction.action_id
    } else {
        "inspect_decision_action"
    }

    $safeNextStep = [ordered]@{
        action_id = $actionId
        action = $actionText
        instruction = ("{0}. Owner module: {1}. Verify evidence before closing." -f $actionText, $targetModule)
        target_module = $targetModule
        why = $why
    }

    if ($sessionContinuationRequired) {
        $safeNextStep.session_id = $sessionId
        $safeNextStep.pending_count = $nextPendingCount
    }

    return [ordered]@{
        decision_action = $safeDecisionAction
        next_step = $safeNextStep
    }
}
