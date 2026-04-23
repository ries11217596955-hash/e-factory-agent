Set-StrictMode -Version Latest

function Get-FailureClass {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FailureStage,
        [string]$ErrorCode = ''
    )

    $stage = ([string]$FailureStage).ToUpperInvariant()
    $code = ([string]$ErrorCode).ToUpperInvariant()

    if ($code -eq 'ROUTE_CONTRACT_BREACH' -or $stage -eq 'REPORT_LAYER') {
        return 'AGENT_DEFECT'
    }

    if (@('ENTRY', 'LINK_FETCH', 'ROUTE_EXTRACTION') -contains $stage) {
        return 'OBJECT_DEFECT'
    }

    if (@('CAPTURE', 'RECONCILIATION') -contains $stage) {
        return 'AUDIT_LIMITATION'
    }

    return 'AGENT_DEFECT'
}

function Get-BuildLadderContract {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$HasTruthfulFailure,
        [Parameter(Mandatory = $true)]
        [bool]$HasSelfDiagnostic,
        [Parameter(Mandatory = $true)]
        [bool]$HasOperatorHandoff
    )

    $layers = @(
        [ordered]@{ order = 1; layer = 'runtime foundation'; status = 'READY' },
        [ordered]@{ order = 2; layer = 'truthful failure'; status = if ($HasTruthfulFailure) { 'READY' } else { 'MISSING' } },
        [ordered]@{ order = 3; layer = 'self-diagnostic'; status = if ($HasSelfDiagnostic) { 'READY' } else { 'MISSING' } },
        [ordered]@{ order = 4; layer = 'operator handoff'; status = if ($HasOperatorHandoff) { 'READY' } else { 'MISSING' } },
        [ordered]@{ order = 5; layer = 'object audit'; status = 'BLOCKED_UNTIL_2_4_READY' },
        [ordered]@{ order = 6; layer = 'audit features'; status = 'BLOCKED_UNTIL_2_4_READY' }
    )

    return [ordered]@{
        order = @($layers)
        lock_enforced = $true
        feature_progress_allowed = [bool]($HasTruthfulFailure -and $HasSelfDiagnostic -and $HasOperatorHandoff)
    }
}

function New-AgentFailureReportText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LastCompletedStage,
        [Parameter(Mandatory = $true)]
        [string]$CurrentFailureStage,
        [Parameter(Mandatory = $true)]
        [ValidateSet('AGENT_DEFECT', 'OBJECT_DEFECT', 'AUDIT_LIMITATION')]
        [string]$FailureClass,
        [Parameter(Mandatory = $true)]
        [string]$RawError,
        [Parameter(Mandatory = $true)]
        [string]$LikelyRootCause,
        [Parameter(Mandatory = $true)]
        [string]$FirstFixStep
    )

    $humanExplanation = switch ([string]$FailureClass) {
        'AGENT_DEFECT' { 'The failure is inside agent logic/contract and must be fixed in agent code before trusting feature progress.' }
        'OBJECT_DEFECT' { 'The failure comes from the audited object (site/content/route behavior), not from the auditing protocol itself.' }
        'AUDIT_LIMITATION' { 'The failure is a boundary of current audit capability and should be handled as instrumentation/coverage limitation.' }
    }

    return @(
        "last_completed_stage=$LastCompletedStage",
        "current_failure_stage=$CurrentFailureStage",
        "failure_class=$FailureClass",
        "raw_error=$RawError",
        "human_explanation=$humanExplanation",
        "likely_root_cause=$LikelyRootCause",
        "first_fix_step=$FirstFixStep"
    ) -join [Environment]::NewLine
}

function New-OperatorHandoffContract {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('AGENT_DEFECT', 'OBJECT_DEFECT', 'AUDIT_LIMITATION')]
        [string]$FailureClass,
        [Parameter(Mandatory = $true)]
        [string]$CurrentFailureStage
    )

    $next1 = switch ([string]$FailureClass) {
        'AGENT_DEFECT' { "Patch agent stage '$CurrentFailureStage' contract and rerun LINK mode." }
        'OBJECT_DEFECT' { "Inspect target object behavior for stage '$CurrentFailureStage' and confirm reproducibility." }
        'AUDIT_LIMITATION' { "Increase instrumentation coverage for '$CurrentFailureStage' without adding new audit signals." }
    }

    return [ordered]@{
        must_read_files = @('RUN_REPORT.json', 'failure_summary.json', 'AGENT_FAILURE_REPORT.txt', 'AGENT_OPERATOR_HANDOFF.json')
        forbidden_moves = @(
            'do not add new audit signals',
            'do not redesign human audit reports',
            'do not touch CI/workflows'
        )
        next_1_fix = $next1
        next_2_optional = 'Re-run with the same BaseUrl after applying next_1_fix and compare deterministic artifacts.'
        next_3_optional = 'Only after stable rerun, continue object audit and feature tasks.'
        rerun_condition = 'Rerun only after next_1_fix is completed and artifacts are generated successfully.'
    }
}
