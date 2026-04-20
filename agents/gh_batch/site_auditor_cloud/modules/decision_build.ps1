function Build-DecisionLayer {
    param(
        [string]$ResolvedMode,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [object]$MissingInputs,
        [object]$Warnings
    )

    $activeOperationLabel = 'initialize'
    $activeExpression = ''
    $leftOperand = $null
    $rightOperand = $null

    try {
        $activeOperationLabel = 'input_normalization'
        $activeExpression = 'Convert-ToHashtableSafe/Convert-ToObjectArraySafe/Convert-ToDecisionWarningStringArray'
        $leftOperand = $LiveLayer
        $rightOperand = $Warnings

        $normalizedSourceLayer = Convert-ToHashtableSafe -Value $SourceLayer
        $normalizedLiveLayer = Convert-ToHashtableSafe -Value $LiveLayer
        $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'summary' -Default @{})
        $routes = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'route_details' -Default @()))
        $normalizedWarnings = @(Convert-ToDecisionWarningStringArray -Value $Warnings)
        $normalizedMissingInputs = @(
            foreach ($item in @(Convert-ToObjectArraySafe -Value $MissingInputs)) {
                $value = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $value
                }
            }
        )
        if ($null -eq $normalizedMissingInputs) {
            $normalizedMissingInputs = @()
        }
        $normalizedMissingInputs = @($normalizedMissingInputs)

        $activeOperationLabel = 'live_summary_extract'
        $activeExpression = 'Safe-Get counters from liveSummary'
        $leftOperand = $liveSummary
        $rightOperand = $null

        $sourceRequired = [bool](Safe-Get -Object $normalizedSourceLayer -Key 'required' -Default $false)
        $sourceOk = [bool](Safe-Get -Object $normalizedSourceLayer -Key 'ok' -Default $false)
        $liveRequired = [bool](Safe-Get -Object $normalizedLiveLayer -Key 'required' -Default $false)
        $liveOk = [bool](Safe-Get -Object $normalizedLiveLayer -Key 'ok' -Default $false)

        $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
        $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
        $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
        $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
        $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
        $totalRoutes = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
        $screenshotCount = [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0)
        $routesWithEvidence = 0
        $priorityRouteCandidates = New-Object System.Collections.ArrayList

        $activeOperationLabel = 'route_iteration'
        $activeExpression = 'foreach route in routes'
        $leftOperand = $routes
        $rightOperand = $null

        foreach ($route in @($routes)) {
            $routeNode = Convert-ToHashtableSafe -Value $route
            $routePath = [string](Safe-Get -Object $routeNode -Key 'route_path' -Default (Safe-Get -Object $routeNode -Key 'url' -Default (Safe-Get -Object $routeNode -Key 'path' -Default '')))
            if ([string]::IsNullOrWhiteSpace($routePath)) { $routePath = '(unknown-route)' }

            $pageFlags = Convert-ToHashtableSafe -Value (Safe-Get -Object $routeNode -Key 'page_flags' -Default @{})
            $issues = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $routeNode -Key 'issues' -Default @()))
            $routeScreenshotCount = [int](Safe-Get -Object $routeNode -Key 'screenshotCount' -Default 0)
            if ($routeScreenshotCount -le 0) {
                $routeScreenshotCount = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $routeNode -Key 'screenshots' -Default @())).Count
                $routeScreenshotCount += @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $routeNode -Key 'issue_screenshots' -Default @())).Count
            }
            if ($routeScreenshotCount -gt 0) {
                $routesWithEvidence++
                $screenshotCount += $routeScreenshotCount
            }

            $isEmpty = [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false)
            $isThin = [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)
            $isContaminated = [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
            $isWeakCta = [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false)
            $isDeadEnd = [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)

            foreach ($issue in @($issues)) {
                $issueNode = Convert-ToHashtableSafe -Value $issue
                $issueClass = [string](Safe-Get -Object $issueNode -Key 'class' -Default '')
                if ($issueClass -eq 'OVERLAY_OR_UI_CONTAMINATION' -or $issueClass -eq 'BROKEN_RENDER_OR_TEMPLATE_LEAKAGE') { $isContaminated = $true }
                if ($issueClass -eq 'EMPTY_ROUTE' -or $issueClass -eq 'DUPLICATE_SHELL_OR_MISSING_CRITICAL_BLOCK') { $isEmpty = $true }
                if ($issueClass -eq 'THIN_CONTENT') { $isThin = $true }
                if ($issueClass -eq 'WEAK_CTA') { $isWeakCta = $true }
                if ($issueClass -eq 'DEAD_END') { $isDeadEnd = $true }
            }

            if ($isEmpty) { $emptyRoutes++ }
            if ($isThin) { $thinRoutes++ }
            if ($isContaminated) { $contaminatedRoutes++ }
            if ($isWeakCta) { $weakCtaRoutes++ }
            if ($isDeadEnd) { $deadEndRoutes++ }

            $severity = 0
            if ($isEmpty) { $severity += 100 }
            if ($isContaminated) { $severity += 70 }
            if ($isThin) { $severity += 50 }
            if ($isWeakCta) { $severity += 30 }
            if ($isDeadEnd) { $severity += 30 }
            if ($routeScreenshotCount -gt 0) { $severity += 5 }

            if ($severity -gt 0) {
                [void]$priorityRouteCandidates.Add(
                    [pscustomobject]@{
                        route_path = [string]$routePath
                        severity   = [int]$severity
                    }
                )
            }
        }

        if ($totalRoutes -le 0) { $totalRoutes = @($routes).Count }
        $visualManifestPresent = [bool](Safe-Get -Object $liveSummary -Key 'visual_manifest_present' -Default $false)
        $visualAuditActive = ($visualManifestPresent -or $screenshotCount -gt 0 -or $routesWithEvidence -gt 0)
        $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default '')
        if ([string]::IsNullOrWhiteSpace($pageQualityStatus)) {
            $pageQualityStatus = if ($totalRoutes -gt 0) { 'EVALUATED' } else { 'NOT_EVALUATED' }
        }

        $priorityRouteCandidates = @($priorityRouteCandidates)

        $activeOperationLabel = 'priority_route_sort'
        $activeExpression = 'Sort-Object normalizedPriorityRouteCandidates by severity/route_path'
        $leftOperand = $priorityRouteCandidates
        $rightOperand = $null

        $normalizedPriorityRouteCandidates = @(
            foreach ($candidate in @($priorityRouteCandidates)) {
                $candidateNode = Convert-ToHashtableSafe -Value $candidate
                $candidateRoutePath = [string](Safe-Get -Object $candidateNode -Key 'route_path' -Default '')
                if ([string]::IsNullOrWhiteSpace($candidateRoutePath)) { continue }

                [pscustomobject]@{
                    route_path = [string]$candidateRoutePath
                    severity   = [int](Convert-ToIntSafe -Value (Safe-Get -Object $candidateNode -Key 'severity' -Default 0))
                }
            }
        )

        $priorityRoutes = @(
            @($normalizedPriorityRouteCandidates) |
                Sort-Object `
                    @{ Expression = { [int]$_.severity }; Descending = $true }, `
                    @{ Expression = { [string]$_.route_path }; Descending = $false } |
                Select-Object -First 5 |
                ForEach-Object { [string]$_.route_path }
        )

        $activeOperationLabel = 'stage_classification'
        $activeExpression = 'Compute stage from normalized counters and gates'
        $leftOperand = $normalizedMissingInputs
        $rightOperand = $priorityRoutes

        $conversionWeak = [int]($weakCtaRoutes + $deadEndRoutes)
        $stage = 'READY'
        if (@($normalizedMissingInputs).Count -gt 0 -or ($sourceRequired -and -not $sourceOk) -or ($liveRequired -and -not $liveOk) -or ($liveRequired -and $totalRoutes -le 0)) {
            $stage = 'BROKEN'
        }
        elseif (-not $visualAuditActive -and $liveRequired) {
            $stage = 'BROKEN'
        }
        elseif ($emptyRoutes -gt 0) {
            $stage = 'STRUCTURE'
        }
        elseif ($contaminatedRoutes -gt 0) {
            $stage = 'UX'
        }
        elseif ($thinRoutes -gt 0) {
            $stage = 'CONTENT'
        }
        elseif ($conversionWeak -gt 0) {
            $stage = 'CONVERSION'
        }

        $activeOperationLabel = 'core_problem_build'
        $activeExpression = 'switch stage -> coreProblem'
        $leftOperand = $stage
        $rightOperand = $null

        $coreProblem = switch ($stage) {
            'BROKEN' {
                if (-not $visualAuditActive -and $liveRequired) {
                    'Visual evidence is missing or not being surfaced truthfully, so the run cannot be trusted.'
                }
                elseif (@($normalizedMissingInputs).Count -gt 0) {
                    "Required inputs are missing, so the auditor cannot produce trustworthy output: $((@($normalizedMissingInputs) | Select-Object -First 5) -join ', ')."
                }
                else {
                    'Runtime or truth boundary is unstable, so decision output is not yet trustworthy.'
                }
            }
            'STRUCTURE' { 'The site still has empty or broken routes, so users hit dead pages before any monetization can work.' }
            'UX' { 'UI contamination or broken render signals reduce trust before the user can decide or act.' }
            'CONTENT' { 'Thin pages do not answer intent strongly enough to support decision and conversion.' }
            'CONVERSION' { 'Routes are visible but weak CTA / dead-end patterns still block action.' }
            default { 'The sampled routes look decision-ready and no deterministic blocker dominates the current run.' }
        }

        $activeOperationLabel = 'p0_build'
        $activeExpression = 'Build p0 list'
        $leftOperand = $coreProblem
        $rightOperand = $stage

        $p0List = New-Object System.Collections.Generic.List[string]
        if ($stage -eq 'BROKEN') {
            if (@($normalizedMissingInputs).Count -gt 0) {
                Add-UniqueString -List $p0List -Value ("Missing inputs: " + ((@($normalizedMissingInputs) | Select-Object -First 5) -join ', '))
            }
            if (-not $sourceOk -and $sourceRequired) {
                Add-UniqueString -List $p0List -Value 'Source layer did not complete successfully.'
            }
            if (-not $liveOk -and $liveRequired) {
                Add-UniqueString -List $p0List -Value 'Live layer did not complete successfully.'
            }
            if (-not $visualAuditActive -and $liveRequired) {
                Add-UniqueString -List $p0List -Value 'Visual audit evidence is missing even though live evaluation was required.'
            }
        }
        if ($emptyRoutes -gt 0) {
            Add-UniqueString -List $p0List -Value "$emptyRoutes route(s) are empty or structurally broken."
        }
        if ($contaminatedRoutes -gt 0) {
            Add-UniqueString -List $p0List -Value "$contaminatedRoutes route(s) show UI contamination or broken render leakage."
        }
        if ($thinRoutes -gt 0) {
            Add-UniqueString -List $p0List -Value "$thinRoutes route(s) remain too thin to support decision quality."
        }
        if ($conversionWeak -gt 0) {
            Add-UniqueString -List $p0List -Value "$conversionWeak route(s) still have weak CTA or dead-end behavior."
        }
        if ($visualAuditActive -and $routesWithEvidence -gt 0) {
            Add-UniqueString -List $p0List -Value "Visual evidence active on $routesWithEvidence route(s); final truth must reflect artifact reality."
        }
        if (@($priorityRoutes).Count -gt 0 -and $stage -ne 'READY') {
            Add-UniqueString -List $p0List -Value ("Priority routes: " + ((@($priorityRoutes) | Select-Object -First 3) -join ', '))
        }
        if ($p0List.Count -eq 0 -and $stage -eq 'READY') {
            Add-UniqueString -List $p0List -Value 'No deterministic blocker detected in this run.'
        }

        $activeOperationLabel = 'action_lists_build'
        $activeExpression = 'Build nowList and afterList'
        $leftOperand = $p0List
        $rightOperand = $stage

        $nowList = New-Object System.Collections.Generic.List[string]
        $afterList = New-Object System.Collections.Generic.List[string]
        switch ($stage) {
            'BROKEN' {
                Add-UniqueString -List $nowList -Value 'Repair the failed truth/runtime boundary, then rerun the same mode.'
                Add-UniqueString -List $nowList -Value 'Trust artifacts over booleans: manifest and screenshots must be reflected in audit_result and summaries.'
                Add-UniqueString -List $afterList -Value 'After truth is stable, classify the dominant site blocker again.'
            }
            'STRUCTURE' {
                Add-UniqueString -List $nowList -Value 'Repair empty or broken shell routes before any optimization work.'
                Add-UniqueString -List $nowList -Value 'Use screenshots to verify each repaired route renders as a real page.'
                Add-UniqueString -List $afterList -Value 'After structure is fixed, deepen content and tighten conversion paths.'
            }
            'UX' {
                Add-UniqueString -List $nowList -Value 'Remove overlays, template leakage, or other visual contamination on priority routes.'
                Add-UniqueString -List $afterList -Value 'After trust is restored, improve content depth and CTA clarity.'
            }
            'CONTENT' {
                Add-UniqueString -List $nowList -Value 'Expand thin routes with direct answer, useful body copy, and clear route purpose.'
                Add-UniqueString -List $afterList -Value 'After content depth improves, tighten CTA and onward navigation.'
            }
            'CONVERSION' {
                Add-UniqueString -List $nowList -Value 'Add clear CTA and onward navigation on weak decision routes.'
                Add-UniqueString -List $afterList -Value 'After conversion blockers are removed, polish UX and maintain evidence coverage.'
            }
            default {
                Add-UniqueString -List $nowList -Value 'Keep the current baseline and rerun after meaningful site changes.'
                Add-UniqueString -List $afterList -Value 'Monitor regression through screenshots and route deltas.'
            }
        }

        foreach ($warning in @($normalizedWarnings | Select-Object -First 3)) {
            if ($p0List.Count -ge 5) { break }
            Add-UniqueString -List $p0List -Value ([string]$warning)
        }

        $activeOperationLabel = 'contradiction_summary_build'
        $activeExpression = 'Build contradictionSummary/siteDiagnosis/maturityReadiness/auditorBaseline'
        $leftOperand = $visualAuditActive
        $rightOperand = $routesWithEvidence

        $contradictionSourceLayer = @{}
        $normalizedContradictionSource = Convert-ToHashtableSafe -Value $normalizedSourceLayer
        foreach ($entry in $normalizedContradictionSource.GetEnumerator()) {
            if ($entry -is [System.Collections.DictionaryEntry]) {
                $entryKey = [string]$entry.Key
                if (-not [string]::IsNullOrWhiteSpace($entryKey)) {
                    $contradictionSourceLayer[$entryKey] = $entry.Value
                }
                continue
            }

            $entryNode = Convert-ToHashtableSafe -Value $entry
            $entryKey = [string](Safe-Get -Object $entryNode -Key 'Key' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($entryKey)) {
                $contradictionSourceLayer[$entryKey] = Safe-Get -Object $entryNode -Key 'Value' -Default $null
            }
        }

        $contradictionLiveLayer = @{}
        $normalizedContradictionLive = Convert-ToHashtableSafe -Value $normalizedLiveLayer
        foreach ($entry in $normalizedContradictionLive.GetEnumerator()) {
            if ($entry -is [System.Collections.DictionaryEntry]) {
                $entryKey = [string]$entry.Key
                if (-not [string]::IsNullOrWhiteSpace($entryKey)) {
                    $contradictionLiveLayer[$entryKey] = $entry.Value
                }
                continue
            }

            $entryNode = Convert-ToHashtableSafe -Value $entry
            $entryKey = [string](Safe-Get -Object $entryNode -Key 'Key' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($entryKey)) {
                $contradictionLiveLayer[$entryKey] = Safe-Get -Object $entryNode -Key 'Value' -Default $null
            }
        }

        $contradictionMissingInputs = @(Convert-ToStringArraySafe -Value $normalizedMissingInputs)

        $contradictionSummary = Convert-ToHashtableSafe -Value (
            Build-ContradictionLayer -SourceLayer $contradictionSourceLayer -LiveLayer $contradictionLiveLayer -MissingInputs $contradictionMissingInputs
        )

        $siteDiagnosis = Convert-ToHashtableSafe -Value (
            Build-SiteDiagnosisLayer -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -MissingInputs $normalizedMissingInputs
        )

        $maturityReadiness = Convert-ToHashtableSafe -Value (
            Build-MaturityReadinessLayer -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary -MissingInputs $normalizedMissingInputs
        )

        $auditorBaseline = Convert-ToHashtableSafe -Value (
            Build-AuditorBaselineCertification -FinalStatus 'FAIL' -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness
        )

        $activeOperationLabel = 'remediation_build'
        $activeExpression = 'Build remediationPackage'
        $leftOperand = $priorityRoutes
        $rightOperand = $nowList

        $remediationPackage = Convert-ToHashtableSafe -Value (
            Build-PrimaryRemediationPackage -LiveLayer $normalizedLiveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary
        )

        if (@($priorityRoutes).Count -eq 0) {
            $packageTargets = @(Convert-ToStringArraySafe -Value (Safe-Get -Object $remediationPackage -Key 'primary_targets' -Default @()))
            if (@($packageTargets).Count -gt 0) {
                $priorityRoutes = @($packageTargets | Select-Object -Unique | Select-Object -First 5)
            }
        }

        $activeOperationLabel = 'product_closeout_build'
        $activeExpression = 'Normalize-ProductCloseout'
        $leftOperand = $stage
        $rightOperand = $coreProblem

        $productCloseout = Convert-ToHashtableSafe -Value (
            Build-ProductCloseoutClassification -FinalStatus 'FAIL' -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness -RemediationPackage $remediationPackage
        )

        $activeOperationLabel = 'repair_hint_build'
        $activeExpression = 'Get-DecisionRepairHint'
        $leftOperand = $priorityRoutes
        $rightOperand = $liveSummary

        $repairHintRaw = Get-DecisionRepairHint -Stage $stage -CoreProblem $coreProblem -PriorityRoutes $priorityRoutes -ResolvedMode $ResolvedMode -MissingInputs $normalizedMissingInputs -LiveSummary $liveSummary
        $repairHint = Convert-ToHashtableSafe -Value $repairHintRaw
        if ($repairHint.Count -eq 0 -and $repairHintRaw -is [System.Collections.IDictionary]) {
            $repairHint = [ordered]@{}
            foreach ($entry in $repairHintRaw.GetEnumerator()) {
                $repairHint[[string]$entry.Key] = $entry.Value
            }
        }

        $activeOperationLabel = 'decision_assemble'
        $activeExpression = 'Assemble final decision ordered hashtable'
        $leftOperand = $repairHint
        $rightOperand = $productCloseout

        $decision = [ordered]@{
            stage = [string]$stage
            core_problem = [string]$coreProblem
            warnings = @($normalizedWarnings)
            missing_inputs = @($normalizedMissingInputs)
            p0 = @($p0List.ToArray() | Select-Object -Unique)
            p1 = @()
            p2 = @()
            problems = @($p0List.ToArray() | Select-Object -Unique)
            do_next = @($nowList.ToArray() | Select-Object -Unique)
            next_actions = @($nowList.ToArray() | Select-Object -Unique)
            do_next_now = @($nowList.ToArray() | Select-Object -Unique)
            do_next_after = @($afterList.ToArray() | Select-Object -Unique)
            do_next_detail = [ordered]@{
                now = @($nowList.ToArray() | Select-Object -Unique)
                after = @($afterList.ToArray() | Select-Object -Unique)
            }
            repair_hint = $repairHint
            priority_routes = @($priorityRoutes)
            site_diagnosis = $siteDiagnosis
            maturity_readiness = $maturityReadiness
            auditor_baseline = $auditorBaseline
            remediation_package = $remediationPackage
            product_closeout = $productCloseout
            contradiction_summary = $contradictionSummary
            clean_state = if ($stage -eq 'READY') { 'CLEAN' } else { 'NOT_CLEAN' }
        }

        return $decision
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-DecisionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $activeOperationLabel -ActiveExpression $activeExpression -LeftOperand $leftOperand -RightOperand $rightOperand -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
            exception_message = $_.Exception.Message
            stage = if (Get-Variable -Name stage -Scope Local -ErrorAction SilentlyContinue) { [string]$stage } else { '' }
            total_routes = if (Get-Variable -Name totalRoutes -Scope Local -ErrorAction SilentlyContinue) { [int]$totalRoutes } else { -1 }
            routes_type = if (Get-Variable -Name routes -Scope Local -ErrorAction SilentlyContinue) { if ($null -eq $routes) { '<null>' } else { $routes.GetType().FullName } } else { '<unset>' }
            live_summary_type = if (Get-Variable -Name liveSummary -Scope Local -ErrorAction SilentlyContinue) { if ($null -eq $liveSummary) { '<null>' } else { $liveSummary.GetType().FullName } } else { '<unset>' }
            priority_routes_type = if (Get-Variable -Name priorityRoutes -Scope Local -ErrorAction SilentlyContinue) { if ($null -eq $priorityRoutes) { '<null>' } else { $priorityRoutes.GetType().FullName } } else { '<unset>' }
            decision_build_stamp = if (Get-Variable -Name DecisionBuildStamp -Scope Script -ErrorAction SilentlyContinue) { [string]$script:DecisionBuildStamp } else { '' }
        })
        throw "Build-DecisionLayer failed at [$activeOperationLabel]: $($_.Exception.Message)"
    }
}

function Convert-ToLegacyDecisionShape {
    param([object]$DecisionRich)

    $decisionNode = Convert-ToHashtableSafe -Value $DecisionRich

    $stage = [string](Safe-Get -Object $decisionNode -Key 'stage' -Default 'READY')
    $coreProblem = [string](Safe-Get -Object $decisionNode -Key 'core_problem' -Default '')

    $p0 = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'p0' -Default @()))
    $p1 = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'p1' -Default @()))
    $p2 = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'p2' -Default @()))
    $doNext = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'do_next' -Default @()))
    $missingInputs = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'missing' -Default @()))

    if (@($missingInputs).Count -eq 0) {
        $missingInputs = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $decisionNode -Key 'missing_inputs' -Default @()))
    }

    $decision = @{}

    $decision["STAGE"] = [string]$stage

    $decision["CORE_PROBLEM"] = [string]$coreProblem

    $decision["P0"] = @(
        foreach ($item in @($p0)) {
            if ($null -ne $item) { [string]$item }
        }
    )

    $decision["P1"] = @(
        foreach ($item in @($p1)) {
            if ($null -ne $item) { [string]$item }
        }
    )

    $decision["P2"] = @(
        foreach ($item in @($p2)) {
            if ($null -ne $item) { [string]$item }
        }
    )

    $decision["DO_NEXT"] = @(
        foreach ($item in @($doNext)) {
            if ($null -ne $item) { [string]$item }
        }
    )

    $decision["MISSING"] = @(
        foreach ($item in @($missingInputs)) {
            if ($null -ne $item) { [string]$item }
        }
    )

    return $decision
}
