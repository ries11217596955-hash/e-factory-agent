function Build-ContradictionLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [string[]]$MissingInputs
    )

    $routes = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $repeatedPatternCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
    $issueRollupTotal =
        [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)

    $routeCandidates = New-Object System.Collections.Generic.List[object]
    $operationLabel = 'C1_prepare_contradiction_candidates'
    $expression = 'materialize route contradiction_candidates into deterministic object[] before route candidate projection'
    $activeRoutePath = ''
    $candidateSource = $null
    $candidateSourceArray = @()
    try {
        foreach ($route in @($routes)) {
            $activeRoutePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
            $candidateSource = Safe-Get -Object $route -Key 'contradiction_candidates' -Default @()
            $candidateSourceArray = Convert-ToObjectArraySafe -Value $candidateSource
            foreach ($candidate in $candidateSourceArray) {
                $routeCandidates.Add([ordered]@{
                        class = [string](Safe-Get -Object $candidate -Key 'class' -Default 'UNKNOWN')
                        scope = 'ROUTE'
                        route_path = $activeRoutePath
                        severity = [string](Safe-Get -Object $candidate -Key 'severity' -Default 'REVIEW')
                        evidence = [string](Safe-Get -Object $candidate -Key 'evidence' -Default '')
                    })
            }
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ContradictionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $candidateSource -RightOperand $candidateSourceArray -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                operation_label = $operationLabel
                expression = $expression
                route_path_if_available = $activeRoutePath
                contradiction_candidate_source_type = if ($null -eq $candidateSource) { '<null>' } else { $candidateSource.GetType().FullName }
                local_collection_type = if ($null -eq $candidateSourceArray) { '<null>' } else { $candidateSourceArray.GetType().FullName }
                local_collection_count = [int]@($candidateSourceArray).Count
                exact_failing_sub_expression = '$routeCandidates.Add([ordered]@{...})'
                error_message = $_.Exception.Message
            })
        throw "Build-ContradictionLayer failed at [$operationLabel]: $($_.Exception.Message)"
    }

    $siteCandidates = New-Object System.Collections.Generic.List[object]

    $sourceEnabled = [bool](Safe-Get -Object $SourceLayer -Key 'enabled' -Default $false)
    $sourceFileCount = [int](Safe-Get -Object (Safe-Get -Object $SourceLayer -Key 'summary' -Default @{}) -Key 'file_count' -Default 0)
    $sourceTopDirs = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $SourceLayer -Key 'summary' -Default @{}) -Key 'top_level_directories' -Default @())
    $thinOrLowValueRoutes = Convert-ToObjectArraySafe -Value @($routes | Where-Object {
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)
        })
    if ($sourceEnabled -and $sourceFileCount -ge 25 -and @($sourceTopDirs).Where({ $_ -ne $null }).Count -ge 2 -and @($thinOrLowValueRoutes).Where({ $_ -ne $null }).Count -gt 0) {
        $siteCandidates.Add([ordered]@{
                class = 'SOURCE_EXPECTS_MORE_THAN_LIVE_DELIVERS'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "source inventory suggests non-trivial implementation (file_count=$sourceFileCount, top_dirs=$(@($sourceTopDirs).Where({ $_ -ne $null }).Count)) while low-value live routes exist ($(@($thinOrLowValueRoutes).Where({ $_ -ne $null }).Count))."
            })
    }

    if ($repeatedPatternCount -gt 0 -and $issueRollupTotal -ge 2) {
        $siteCandidates.Add([ordered]@{
                class = 'SUMMARY_UNDERSTATES_PATTERN'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "repeated_pattern_count=$repeatedPatternCount with aggregate issue observations=$issueRollupTotal can make top-line summary sound milder than route-level evidence."
            })
    }

    $degradedState = ($pageQualityStatus -in @('PARTIAL', 'NOT_EVALUATED')) -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0
    $evidenceRich = (@($routes).Where({ $_ -ne $null }).Count -ge 3) -and (@($routeCandidates).Where({ $_ -ne $null }).Count -ge 2)
    if ($degradedState -and $evidenceRich) {
        $siteCandidates.Add([ordered]@{
                class = 'PARTIAL_BUT_EVIDENCE_RICH'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "run degradation detected (page_quality_status=$pageQualityStatus, missing_inputs=$(@($MissingInputs).Where({ $_ -ne $null }).Count)) but route-level contradiction evidence is still meaningful (routes=$(@($routes).Where({ $_ -ne $null }).Count), route_candidates=$(@($routeCandidates).Where({ $_ -ne $null }).Count))."
            })
    }

    $operationLabel = 'C2_combine_contradiction_candidates'
    $expression = 'explicit object[] materialization + local object[] combine container (no implicit list arithmetic)'
    $routeCandidateArray = @()
    $siteCandidateArray = @()
    $allCandidates = @()
    $classCounts = @{}
    $combineExpression = '$combinedCandidates += $routeCandidateArray; $combinedCandidates += $siteCandidateArray'

    try {
        $routeCandidateArray = [object[]](Convert-ToObjectArraySafe -Value $routeCandidates)
        $siteCandidateArray = [object[]](Convert-ToObjectArraySafe -Value $siteCandidates)

        $combinedCandidates = New-Object System.Collections.ArrayList
        foreach ($candidate in $routeCandidateArray) {
            [void]$combinedCandidates.Add($candidate)
        }
        foreach ($candidate in $siteCandidateArray) {
            [void]$combinedCandidates.Add($candidate)
        }
        $allCandidates = [object[]]$combinedCandidates.ToArray([object])

        $operationLabel = 'C3_build_contradiction_class_counts'
        foreach ($candidate in $allCandidates) {
            $className = [string](Safe-Get -Object $candidate -Key 'class' -Default 'UNKNOWN')
            if (-not $classCounts.ContainsKey($className)) {
                $classCounts[$className] = 0
            }
            $classCounts[$className] = [int]$classCounts[$className] + 1
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ContradictionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $routeCandidateArray -RightOperand $siteCandidateArray -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                operation_label = $operationLabel
                expression = $expression
                route_candidates_type = if ($null -eq $routeCandidates) { '<null>' } else { $routeCandidates.GetType().FullName }
                site_candidates_type = if ($null -eq $siteCandidates) { '<null>' } else { $siteCandidates.GetType().FullName }
                route_candidate_array_type = if ($null -eq $routeCandidateArray) { '<null>' } else { $routeCandidateArray.GetType().FullName }
                site_candidate_array_type = if ($null -eq $siteCandidateArray) { '<null>' } else { $siteCandidateArray.GetType().FullName }
                exact_combine_expression = $combineExpression
                route_candidate_count = [int]@($routeCandidateArray).Count
                site_candidate_count = [int]@($siteCandidateArray).Count
                error_message = $_.Exception.Message
            })
        throw "Build-ContradictionLayer failed at [$operationLabel]: $($_.Exception.Message)"
    }

    return @{
        route_candidates = @($routeCandidateArray)
        site_candidates = @($siteCandidateArray)
        candidates = @($allCandidates)
        class_counts = $classCounts
        total_candidates = [int](@($allCandidates) | Where-Object { $_ -ne $null }).Count
        route_candidate_count = [int](@($routeCandidateArray) | Where-Object { $_ -ne $null }).Count
        site_candidate_count = [int](@($siteCandidateArray) | Where-Object { $_ -ne $null }).Count
    }
}
