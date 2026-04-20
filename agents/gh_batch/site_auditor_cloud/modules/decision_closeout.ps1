function Build-ProductCloseoutClassification {
    param(
        [string]$FinalStatus,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [hashtable]$SiteDiagnosis,
        [hashtable]$MaturityReadiness,
        [hashtable]$RemediationPackage
    )

    $activeOperationLabel = 'initialize'
    $activeExpression = ''

    try {
        $activeOperationLabel = 'normalize/source_layer'
        $activeExpression = 'Convert-ToHashtableSafe -Value $SourceLayer'
        $normalizedSourceLayer = Convert-ToHashtableSafe -Value $SourceLayer
        $activeOperationLabel = 'normalize/live_layer'
        $activeExpression = 'Convert-ToHashtableSafe -Value $LiveLayer'
        $normalizedLiveLayer = Convert-ToHashtableSafe -Value $LiveLayer
        $activeOperationLabel = 'normalize/contradiction_summary'
        $activeExpression = 'Convert-ToHashtableSafe -Value $ContradictionSummary'
        $normalizedContradictionSummary = Convert-ToHashtableSafe -Value $ContradictionSummary
        $activeOperationLabel = 'normalize/site_diagnosis'
        $activeExpression = 'Convert-ToHashtableSafe -Value $SiteDiagnosis'
        $normalizedSiteDiagnosis = Convert-ToHashtableSafe -Value $SiteDiagnosis
        $activeOperationLabel = 'normalize/maturity_readiness'
        $activeExpression = 'Convert-ToHashtableSafe -Value $MaturityReadiness'
        $normalizedMaturityReadiness = Convert-ToHashtableSafe -Value $MaturityReadiness
        $activeOperationLabel = 'normalize/remediation_package'
        $activeExpression = 'Convert-ToHashtableSafe -Value $RemediationPackage'
        $normalizedRemediationPackage = Convert-ToHashtableSafe -Value $RemediationPackage

    $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'summary' -Default @{})
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'none')
    $routeCount = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
    $screenshotCount = [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $normalizedSiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $maturityClass = [string](Safe-Get -Object $normalizedMaturityReadiness -Key 'class' -Default 'NOT_READY')

    $classCounts = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedContradictionSummary -Key 'class_counts' -Default @{})
    $totalCandidatesRaw = Safe-Get -Object $normalizedContradictionSummary -Key 'total_candidates' -Default $null
    $hasTotalCandidates = $null -ne $totalCandidatesRaw
    $contradictionHasCoreShape = ($classCounts.Count -ge 0) -and $hasTotalCandidates

    $packageName = [string](Safe-Get -Object $normalizedRemediationPackage -Key 'package_name' -Default '')
    $packageTargets = Convert-ToStringArraySafe -Value (Safe-Get -Object $normalizedRemediationPackage -Key 'primary_targets' -Default @())
    $packageTargetsArray = @($packageTargets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $packageTargetCount = @($packageTargetsArray).Count

    $checksByName = [ordered]@{
        runtime_stability = if ($FinalStatus -ne 'FAIL' -and $failureStage -in @('none', '')) { 'PASS' } else { 'FAIL' }
        source_live_evidence_integrity = if ([bool](Safe-Get -Object $normalizedLiveLayer -Key 'enabled' -Default $false) -and [bool](Safe-Get -Object $normalizedLiveLayer -Key 'ok' -Default $false) -and $routeCount -gt 0 -and $screenshotCount -gt 0 -and (-not [bool](Safe-Get -Object $normalizedSourceLayer -Key 'required' -Default $false) -or [bool](Safe-Get -Object $normalizedSourceLayer -Key 'ok' -Default $false))) { 'PASS' } else { 'FAIL' }
        page_quality_usefulness = if ($pageQualityStatus -eq 'EVALUATED') { 'PASS' } else { 'FAIL' }
        contradiction_usefulness = if ($contradictionHasCoreShape) { 'PASS' } else { 'FAIL' }
        diagnosis_usefulness = if ($diagnosisClass -ne 'UNKNOWN') { 'PASS' } else { 'FAIL' }
        maturity_usefulness = if ($maturityClass -ne 'NOT_READY') { 'PASS' } else { 'FAIL' }
        operator_output_usefulness = if (-not [string]::IsNullOrWhiteSpace([string](Safe-Get -Object $normalizedRemediationPackage -Key 'why_first' -Default ''))) { 'PASS' } else { 'FAIL' }
        remediation_package_usefulness = if (-not [string]::IsNullOrWhiteSpace($packageName) -and $packageTargetCount -gt 0) { 'PASS' } else { 'FAIL' }
        analyst_brief_usefulness = if ($pageQualityStatus -in @('EVALUATED', 'PARTIAL') -and $routeCount -gt 0) { 'PASS' } else { 'FAIL' }
        report_bundle_consistency = if ($FinalStatus -in @('PASS', 'PARTIAL', 'FAIL')) { 'PASS' } else { 'FAIL' }
    }

    $failureMap = [ordered]@{
        runtime_stability = 'RUNTIME_STABILITY'
        source_live_evidence_integrity = 'SOURCE_LIVE_EVIDENCE_INTEGRITY'
        page_quality_usefulness = 'PAGE_QUALITY_USEFULNESS'
        contradiction_usefulness = 'CONTRADICTION_USEFULNESS'
        diagnosis_usefulness = 'DIAGNOSIS_USEFULNESS'
        maturity_usefulness = 'MATURITY_USEFULNESS'
        operator_output_usefulness = 'OPERATOR_OUTPUT_USEFULNESS'
        remediation_package_usefulness = 'REMEDIATION_PACKAGE_USEFULNESS'
        analyst_brief_usefulness = 'ANALYST_BRIEF_USEFULNESS'
        report_bundle_consistency = 'REPORT_BUNDLE_CONSISTENCY'
    }

    $failedKey = ''
    foreach ($key in @($checksByName.Keys)) {
        if ([string]$checksByName[$key] -eq 'FAIL') {
            $failedKey = [string]$key
            break
        }
    }

    $classification = 'PRODUCT_READY_BASELINE'
    if (-not [string]::IsNullOrWhiteSpace($failedKey)) {
        $classification = "BLOCKED_BY_$([string]$failureMap[$failedKey])"
    }

    $confidence = 'medium'
    if ($classification -eq 'PRODUCT_READY_BASELINE' -and $FinalStatus -eq 'PASS' -and $pageQualityStatus -eq 'EVALUATED') {
        $confidence = 'high'
    }
    elseif ($FinalStatus -eq 'FAIL' -or $pageQualityStatus -in @('NOT_EVALUATED', 'PARTIAL') -or $diagnosisClass -eq 'UNKNOWN') {
        $confidence = 'low'
    }

        $activeOperationLabel = 'list/materialize/checks_enumerator'
        $activeExpression = '@($checksByName.GetEnumerator())'
        $checksEntries = @($checksByName.GetEnumerator())

        $activeOperationLabel = 'list/create/checks'
        $activeExpression = 'New-Object System.Collections.Generic.List[object]'
        $checks = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($checksEntries)) {
            $checkItem = [ordered]@{
                name = [string]$entry.Key
                status = [string]$entry.Value
            }
            $activeOperationLabel = 'list/add/checks_item'
            $activeExpression = '$checks.Add($checkItem)'
            $checks.Add($checkItem)
        }

    $reasonText = 'Deterministic closeout checks passed for baseline operator use.'
    if (-not [string]::IsNullOrWhiteSpace($failedKey)) {
        $reasonText = "Product closeout blocked by $failedKey."
    }

    $evidence = Convert-ToStringArraySafe -Value @(
        [string]"final_status=$FinalStatus failure_stage=$failureStage page_quality_status=$pageQualityStatus",
        [string]"route_count=$routeCount screenshot_count=$screenshotCount package_name=$packageName package_targets=$packageTargetCount",
        [string]"site_diagnosis=$diagnosisClass maturity=$maturityClass contradiction_shape=$contradictionHasCoreShape"
    )

        $activeOperationLabel = 'assemble/final_closeout_object'
        $activeExpression = '@{ class=...; reason=...; confidence=...; checks=...; evidence=... }'
        return @{
            class = [string]$classification
            reason = [string]$reasonText
            confidence = [string]$confidence
            checks = @($checks)
            evidence = @($evidence)
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ProductCloseoutClassification' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $activeOperationLabel -ActiveExpression $activeExpression -LeftOperand $FinalStatus -RightOperand $normalizedRemediationPackage -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
            error_message = [string]$_.Exception.Message
            failure_kind = 'product_closeout_classification_instrumented_boundary'
        })
        throw
    }
}

function Convert-ToProductStatus {
    param(
        [hashtable]$Decision,
        [string]$FinalStatus
    )

    $activeOperationLabel = 'initialize'
    $activeExpression = ''

    try {
        $activeOperationLabel = 'normalize/decision'
        $activeExpression = 'Convert-ToHashtableSafe -Value $Decision'
        $normalizedInput = Convert-ToHashtableSafe -Value $Decision
        $activeOperationLabel = 'normalize/raw_closeout'
        $activeExpression = 'Safe-Get -Object $normalizedInput -Key product_closeout'
        $rawCloseout = Safe-Get -Object $normalizedInput -Key 'product_closeout' -Default $null
        if ($null -eq $rawCloseout) {
            $rawCloseout = $normalizedInput
        }

        $activeOperationLabel = 'normalize/closeout_shape'
        $activeExpression = 'Convert-ToHashtableSafe -Value (Normalize-ProductCloseout -Value $rawCloseout)'
        $normalizedCloseout = Convert-ToHashtableSafe -Value (Normalize-ProductCloseout -Value $rawCloseout)
        $activeOperationLabel = 'cast/string_fields'
        $activeExpression = 'class/reason/confidence string extraction'
        $closeoutClass = [string](Safe-Get -Object $normalizedCloseout -Key 'class' -Default 'BLOCKED_BY_UNKNOWN')
        $reason = [string](Safe-Get -Object $normalizedCloseout -Key 'reason' -Default 'Product closeout classification was not generated.')
        $confidence = [string](Safe-Get -Object $normalizedCloseout -Key 'confidence' -Default 'low')

        if ($confidence -notin @('high', 'medium', 'low')) { $confidence = 'low' }

        $status = 'FAIL'
        if ($closeoutClass -eq 'PRODUCT_READY_BASELINE') {
            $status = 'SUCCESS'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($reason)) {
            $status = 'NEEDS_FIX'
        }

        $activeOperationLabel = 'assemble/final_product_status'
        $activeExpression = '[ordered]@{ status=... }'
        return [ordered]@{
            status = [string]$status
            reason = [string]$reason
            confidence = [string]$confidence
            source_closeout_class = [string]$closeoutClass
            run_status = [string]$FinalStatus
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Convert-ToProductStatus' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $activeOperationLabel -ActiveExpression $activeExpression -LeftOperand $Decision -RightOperand $FinalStatus -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
            error_message = [string]$_.Exception.Message
            failure_kind = 'product_status_conversion_instrumented_boundary'
        })
        throw
    }
}
