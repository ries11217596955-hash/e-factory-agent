function Build-SiteDiagnosisLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [string[]]$MissingInputs
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $routeDetails = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
    $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
    $dominantPatternLabel = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default '')
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')

    $totalRoutes = [int]@($routeDetails).Count
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
    $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $repeatedPatternCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $conversionWeakRoutes = [int]($weakCtaRoutes + $deadEndRoutes)
    $thinOrEmptyRoutes = [int]($emptyRoutes + $thinRoutes)
    $nonEmptyRoutes = if ($totalRoutes -gt $emptyRoutes) { [int]($totalRoutes - $emptyRoutes) } else { 0 }

    $siteClass = 'PARTIAL_PRODUCT_SYSTEM'
    $reason = 'Site has partially working evidence but quality is uneven across route signals.'
    $evidence = New-Object System.Collections.Generic.List[string]

    if (-not $LiveLayer.enabled -or -not $LiveLayer.ok -or $totalRoutes -eq 0 -or $pageQualityStatus -eq 'NOT_EVALUATED') {
        $siteClass = 'BROKEN_SYSTEM'
        $reason = 'Live system evidence is missing or degraded, so the audited site behavior is not reliably operational.'
    }
    elseif ($contaminatedRoutes -ge 2 -or ($totalRoutes -gt 0 -and ($contaminatedRoutes * 2) -ge $totalRoutes -and $contaminatedRoutes -ge 1)) {
        $siteClass = 'TRUST_CONTAMINATED_SYSTEM'
        $reason = 'Trust contamination repeats across meaningful routes, weakening core credibility signals.'
    }
    elseif ($totalRoutes -gt 0 -and $thinOrEmptyRoutes -ge [Math]::Ceiling($totalRoutes * 0.60) -and $conversionWeakRoutes -ge 1) {
        $siteClass = 'CONTENT_SHELL'
        $reason = 'Most sampled routes are empty/thin and conversion flow is weak, indicating shell-like site behavior.'
    }
    elseif ($totalRoutes -gt 0 -and $emptyRoutes -eq 0 -and $thinRoutes -ge [Math]::Ceiling($totalRoutes * 0.50)) {
        $siteClass = 'STRUCTURALLY_PRESENT_BUT_THIN'
        $reason = 'Routes are present but content depth is repeatedly thin across the sample.'
    }
    elseif ($nonEmptyRoutes -ge 2 -and $conversionWeakRoutes -ge [Math]::Max(2, [Math]::Ceiling($totalRoutes * 0.50))) {
        $siteClass = 'WEAK_CONVERSION_SYSTEM'
        $reason = 'Routes are mostly non-empty but conversion and onward decision paths are consistently weak.'
    }
    elseif ($pageQualityStatus -eq 'EVALUATED' -and $thinOrEmptyRoutes -eq 0 -and $conversionWeakRoutes -eq 0 -and $contaminatedRoutes -eq 0 -and $contradictionTotal -eq 0) {
        $siteClass = 'DECISION_CAPABLE_SYSTEM'
        $reason = 'Route quality and trust signals are consistently healthy with no deterministic contradiction alerts.'
    }
    elseif ($pageQualityStatus -eq 'EVALUATED' -and $emptyRoutes -eq 0 -and $contaminatedRoutes -eq 0 -and $conversionWeakRoutes -le 1 -and $thinRoutes -le 1) {
        $siteClass = 'HEALTHY_BUT_EARLY'
        $reason = 'Core signals are mostly healthy with only light early-stage quality gaps.'
    }
    elseif ($conversionWeakRoutes -ge 1 -and $thinOrEmptyRoutes -le [Math]::Max(1, [Math]::Floor($totalRoutes * 0.34))) {
        $siteClass = 'WEAK_DECISION_SYSTEM'
        $reason = 'Decision-path weakness is the dominant issue while baseline content structure is mostly present.'
    }

    $evidence.Add("route_count=$totalRoutes empty=$emptyRoutes thin=$thinRoutes weak_cta=$weakCtaRoutes dead_end=$deadEndRoutes contaminated=$contaminatedRoutes")
    $evidence.Add("page_quality_status=$pageQualityStatus repeated_pattern_count=$repeatedPatternCount contradiction_candidates=$contradictionTotal")
    if (-not [string]::IsNullOrWhiteSpace($dominantPatternLabel)) {
        $evidence.Add("dominant_pattern=$dominantPatternLabel")
    }
    if (@($MissingInputs).Where({ $_ -ne $null }).Count -gt 0) {
        $evidence.Add("missing_inputs=$(@($MissingInputs).Where({ $_ -ne $null }).Count)")
    }

    $confidence = 'HIGH'
    $degradedRun = ($pageQualityStatus -in @('PARTIAL', 'NOT_EVALUATED')) -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0 -or (-not $LiveLayer.ok)
    if ($degradedRun -or $totalRoutes -lt 3) {
        $confidence = 'MEDIUM'
    }
    if ($pageQualityStatus -eq 'NOT_EVALUATED' -or $totalRoutes -eq 0 -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0 -or (-not $LiveLayer.ok)) {
        $confidence = 'LOW'
    }
    elseif ($confidence -eq 'HIGH' -and $contradictionTotal -ge 3) {
        $confidence = 'MEDIUM'
    }
    elseif ($confidence -eq 'MEDIUM' -and $contradictionTotal -ge 4) {
        $confidence = 'LOW'
    }

    return @{
        class = $siteClass
        reason = $reason
        evidence = @($evidence | Select-Object -First 4)
        confidence = $confidence
    }
}

function Build-MaturityReadinessLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$SiteDiagnosis,
        [hashtable]$ContradictionSummary,
        [string[]]$MissingInputs
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $totalRoutes = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $conversionWeak = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0) + [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $evidenceCoverage = Safe-Get -Object $liveSummary -Key 'evidence_coverage' -Default @{}
    $evidenceRichness = [string](Safe-Get -Object $evidenceCoverage -Key 'evidence_richness' -Default 'SPARSE')
    $missingCount = (@($MissingInputs) | Where-Object { $_ -ne $null }).Count

    $class = 'NOT_READY'
    $reason = 'Run or route-quality evidence is insufficient for release review.'

    if ($missingCount -gt 0 -or -not $LiveLayer.enabled -or $pageQualityStatus -eq 'NOT_EVALUATED' -or $totalRoutes -eq 0) {
        $class = 'NOT_READY'
        $reason = 'Critical runtime evidence is missing or page-quality evaluation did not complete.'
    }
    elseif ($diagnosisClass -in @('BROKEN_SYSTEM', 'CONTENT_SHELL', 'TRUST_CONTAMINATED_SYSTEM')) {
        $class = 'EARLY_STRUCTURE_ONLY'
        $reason = 'System structure is present but deterministic quality/trust blockers dominate.'
    }
    elseif ($emptyRoutes -gt 0 -or $contaminatedRoutes -gt 0) {
        $class = 'PARTIALLY_USABLE'
        $reason = 'Some routes are usable, but empty or trust-contaminated routes block broad reliability.'
    }
    elseif ($thinRoutes -ge 1 -or $conversionWeak -ge 2 -or $evidenceRichness -eq 'SPARSE') {
        $class = 'USABLE_BUT_WEAK'
        $reason = 'Core routes are functioning, but quality depth/conversion coverage remains weak.'
    }
    elseif ($contradictionTotal -ge 3) {
        $class = 'ANALYST_REVIEW_REQUIRED'
        $reason = 'Contradiction density is high enough that analyst verification is required before release review.'
    }
    else {
        $class = 'RELEASE_REVIEW_READY'
        $reason = 'Deterministic route-quality, contradiction, and evidence-coverage checks are consistently healthy.'
    }

    $confidence = 'HIGH'
    if ($evidenceRichness -eq 'SPARSE' -or $totalRoutes -lt 3 -or $pageQualityStatus -eq 'PARTIAL') {
        $confidence = 'MEDIUM'
    }
    if ($pageQualityStatus -eq 'NOT_EVALUATED' -or $missingCount -gt 0 -or -not $LiveLayer.ok) {
        $confidence = 'LOW'
    }

    $evidence = @(
        "page_quality_status=$pageQualityStatus total_routes=$totalRoutes evidence_richness=$evidenceRichness",
        "empty_routes=$emptyRoutes thin_routes=$thinRoutes conversion_weak_routes=$conversionWeak contaminated_routes=$contaminatedRoutes",
        "site_diagnosis=$diagnosisClass contradiction_candidates=$contradictionTotal",
        "missing_inputs=$missingCount"
    )

    return @{
        class = $class
        reason = $reason
        evidence = @($evidence)
        confidence = $confidence
    }
}

function Build-AuditorBaselineCertification {
    param(
        [string]$FinalStatus,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [hashtable]$SiteDiagnosis,
        [hashtable]$MaturityReadiness
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'none')
    $evidenceCoverage = Safe-Get -Object $liveSummary -Key 'evidence_coverage' -Default @{}
    $evidenceRichness = [string](Safe-Get -Object $evidenceCoverage -Key 'evidence_richness' -Default 'SPARSE')
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $siteDiagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $maturityClass = [string](Safe-Get -Object $MaturityReadiness -Key 'class' -Default 'NOT_READY')

    $checks = [ordered]@{
        runtime_path_health = if ($FinalStatus -ne 'FAIL') { 'PASS' } else { 'FAIL' }
        repo_binding_truth = if (-not $SourceLayer.required -or [bool]$SourceLayer.ok) { 'PASS' } else { 'FAIL' }
        visual_evidence_truth = if ([bool]$LiveLayer.enabled -and [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0) -gt 0) { 'PASS' } else { 'FAIL' }
        page_quality_evaluation_truth = if ($pageQualityStatus -in @('EVALUATED', 'PARTIAL')) { 'PASS' } else { 'FAIL' }
        contradiction_layer_truth = if ($null -ne $ContradictionSummary) { 'PASS' } else { 'FAIL' }
        diagnosis_layer_truth = if ($siteDiagnosisClass -ne 'UNKNOWN') { 'PASS' } else { 'FAIL' }
        maturity_layer_truth = if ($maturityClass -ne 'NOT_READY' -or $pageQualityStatus -ne 'NOT_EVALUATED') { 'PASS' } else { 'FAIL' }
        operator_output_usefulness = if ($FinalStatus -ne 'FAIL' -or [bool]$LiveLayer.enabled) { 'PASS' } else { 'FAIL' }
        analyst_brief_usefulness = if ($FinalStatus -ne 'FAIL' -or [bool]$LiveLayer.enabled) { 'PASS' } else { 'FAIL' }
        bundle_report_consistency = if ($FinalStatus -in @('PASS', 'PARTIAL', 'FAIL')) { 'PASS' } else { 'FAIL' }
    }

    $failedChecks = @($checks.Keys | Where-Object { [string]$checks[$_] -eq 'FAIL' })
    $classification = 'BASELINE_READY'
    if (@($failedChecks).Where({ $_ -ne $null }).Count -gt 0) {
        $classification = "BLOCKED_BY_$($failedChecks[0].ToUpperInvariant())"
    }

    $evidence = @(
        "final_status=$FinalStatus page_quality_status=$pageQualityStatus failure_stage=$failureStage",
        "source_ok=$([bool]$SourceLayer.ok) live_enabled=$([bool]$LiveLayer.enabled) live_ok=$([bool]$LiveLayer.ok)",
        "evidence_richness=$evidenceRichness contradiction_candidates=$contradictionTotal",
        "site_diagnosis=$siteDiagnosisClass maturity=$maturityClass"
    )

    return @{
        class = $classification
        reason = if ($classification -eq 'BASELINE_READY') { 'All baseline gate checks passed for deterministic runtime and reporting layers.' } else { "Baseline gate blocked by $($failedChecks[0])." }
        confidence = if ($FinalStatus -eq 'PASS') { 'HIGH' } elseif ($FinalStatus -eq 'PARTIAL') { 'MEDIUM' } else { 'LOW' }
        checks = $checks
        evidence = @($evidence)
    }
}
