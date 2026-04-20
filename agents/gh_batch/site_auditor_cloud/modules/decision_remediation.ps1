function Build-PrimaryRemediationPackage {
    param(
        [hashtable]$LiveLayer,
        [hashtable]$SiteDiagnosis,
        [hashtable]$ContradictionSummary
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $routeDetails = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
    $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $conversionWeakRoutes = [int]($weakCtaRoutes + $deadEndRoutes)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')

    $packageName = 'MIXED_RECOVERY_PACKAGE'
    $packageGoal = 'Stabilize route quality and eliminate the highest repeated blocker cluster first.'
    $whyFirst = 'No single blocker dominates; start with the largest repeated quality cluster to reduce multi-route risk quickly.'
    $successCheck = 'Re-run SITE_AUDITOR and confirm lower empty/thin/contamination counts plus PAGE QUALITY STATUS=EVALUATED.'
    $targetSelector = { param([object]$route) $true }

    if ($pageQualityStatus -eq 'NOT_EVALUATED') {
        $packageName = 'CORE_ROUTE_RECOVERY_PACKAGE'
        $packageGoal = 'Restore complete route evidence generation so page-quality evaluation can run deterministically.'
        $whyFirst = 'Without evaluated route quality, downstream diagnosis and remediation prioritization remain unreliable.'
        $successCheck = 'PAGE QUALITY STATUS becomes EVALUATED and no route normalization/output-writing failure stage remains.'
        $targetSelector = {
            param([object]$route)
            $status = [int](Safe-Get -Object $route -Key 'status' -Default 0)
            ($status -eq 0 -or $status -ge 400)
        }
    }
    elseif ($contaminatedRoutes -ge [Math]::Max(2, [Math]::Max($conversionWeakRoutes, ($emptyRoutes + $thinRoutes)))) {
        $packageName = 'TRUST_CLEANUP_PACKAGE'
        $packageGoal = 'Remove repeated trust-contamination markers before conversion or optimization work.'
        $whyFirst = 'Trust contamination undermines every route narrative and can invalidate otherwise acceptable conversion signals.'
        $successCheck = 'contaminated_routes drops to 0 and contradiction classes tied to contamination are reduced.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
        }
    }
    elseif (($emptyRoutes + $thinRoutes) -ge [Math]::Max(2, $conversionWeakRoutes)) {
        $packageName = 'CORE_ROUTE_RECOVERY_PACKAGE'
        $packageGoal = 'Recover empty/thin core routes before tuning secondary conversion details.'
        $whyFirst = 'Route quality recovery restores baseline utility and prevents optimization work on non-viable pages.'
        $successCheck = 'empty_routes=0 and thin_routes reduced to <=1 on the next run.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)
        }
    }
    elseif ($conversionWeakRoutes -ge 2 -or $diagnosisClass -in @('WEAK_DECISION_SYSTEM', 'WEAK_CONVERSION_SYSTEM')) {
        $packageName = 'CONVERSION_RECOVERY_PACKAGE'
        $packageGoal = 'Repair weak CTA and dead-end navigation paths on high-intent routes.'
        $whyFirst = 'Conversion-path failure blocks practical outcomes even when pages appear content-complete.'
        $successCheck = 'weak_cta_routes + dead_end_routes drops below 2 with no repeated conversion weak pattern.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)
        }
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($route in @($routeDetails)) {
        $path = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (& $targetSelector $route) {
            $targets.Add($path)
        }
    }
    $targetsArray = @($targets) | Where-Object { $_ -ne $null }
    if (@($targetsArray).Where({ $_ -ne $null }).Count -eq 0) {
        foreach ($route in @($routeDetails | Select-Object -First 3)) {
            $path = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $targets.Add($path)
            }
        }
    }

    $reasonEvidence = @(
        "page_quality_status=$pageQualityStatus empty=$emptyRoutes thin=$thinRoutes weak_cta=$weakCtaRoutes dead_end=$deadEndRoutes contaminated=$contaminatedRoutes contradiction_candidates=$contradictionTotal",
        "site_diagnosis=$diagnosisClass"
    )

    return @{
        package_name = $packageName
        package_goal = $packageGoal
        primary_targets = @($targets | Select-Object -Unique | Select-Object -First 5)
        why_first = $whyFirst
        success_check = $successCheck
        evidence = @($reasonEvidence)
    }
}

function Get-DecisionRepairHint {
    param(
        [string]$Stage,
        [string]$CoreProblem,
        [object[]]$PriorityRoutes,
        [string]$ResolvedMode,
        [string[]]$MissingInputs,
        [object]$LiveSummary
    )

    $normalizedStage = [string]$Stage
    if ([string]::IsNullOrWhiteSpace($normalizedStage)) { $normalizedStage = 'BROKEN' }

    $brokenBlock = switch ($normalizedStage) {
        'BROKEN' { 'INPUT_VALIDATION_OR_LIVE_AUDIT' }
        'STRUCTURE' { 'ROUTE_STRUCTURE_AND_EMPTY_SHELLS' }
        'CONTENT' { 'ROUTE_CONTENT_DEPTH' }
        'UX' { 'VISUAL_TRUST_AND_RENDERING' }
        'CONVERSION' { 'CTA_AND_ONWARD_NAVIGATION' }
        default { 'REGRESSION_MONITORING' }
    }

    $nextAction = switch ($normalizedStage) {
        'BROKEN' { 'Fix missing inputs or failed runtime node, then rerun the same mode.' }
        'STRUCTURE' { 'Repair empty/broken routes first, then rerun to confirm structure is stable.' }
        'CONTENT' { 'Expand thin routes with primary content before polishing other layers.' }
        'UX' { 'Remove contamination/render defects visible in screenshots, then rerun.' }
        'CONVERSION' { 'Add clear CTAs and onward navigation on weak routes, then rerun.' }
        default { 'Keep monitoring and rerun after major site changes.' }
    }

    $failureStage = [string](Safe-Get -Object $LiveSummary -Key 'failure_stage' -Default '')
    if ([string]::IsNullOrWhiteSpace($failureStage)) { $failureStage = $normalizedStage }

    return [ordered]@{
        target_file = 'agents/gh_batch/site_auditor_cloud/agent.ps1'
        broken_block = $brokenBlock
        reason = [string]$CoreProblem
        next_action = $nextAction
        failed_stage = $failureStage
        mode = [string]$ResolvedMode
        missing_inputs = @(Convert-ToStringArraySafe -Value $MissingInputs)
        priority_routes = @(Convert-ToStringArraySafe -Value $PriorityRoutes | Select-Object -First 5)
    }
}
