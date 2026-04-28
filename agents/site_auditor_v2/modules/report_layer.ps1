function New-SystemProblemFromFindings {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$AuditConfidence,
        [Parameter(Mandatory = $true)][object]$SortedFindings,
        [Parameter(Mandatory = $true)][object]$ContextValidHighFindings,
        [Parameter(Mandatory = $true)][object]$SortedLimitationFindings,
        [Parameter(Mandatory = $true)][object]$MicroClusters,
        [Parameter(Mandatory = $true)][int]$P0Count,
        [Parameter(Mandatory = $true)][int]$P1Count
    )

    $systemProblem = [ordered]@{
        problem_type = 'NO_CONFIRMED_SYSTEM_DEFECT'
        category = 'CLEAN'
        title = 'No confirmed system-level defects in checked scope'
        description = 'No repeated HIGH-confidence defect pattern was observed across normalized surfaces in the checked scope.'
        description_ru = 'Повторяющийся дефект высокого уровня уверенности по нормализованным поверхностям в проверенном объёме не выявлен.'
        affected_surfaces_count = 0
        representative_examples = @()
        strongest_action = if (@('LOW', 'MEDIUM') -contains [string]$AuditConfidence) { 'Expand route sample and rerun LINK mode for broader coverage.' } else { 'Keep monitoring and rerun when scope changes.' }
        confidence = [string]$AuditConfidence
        source_cluster = 'NONE'
        interaction_explanation = [ordered]@{
            entry_surface = 'UNKNOWN'
            expected_outcome = 'Stable behavior across checked surfaces.'
            actual_outcome = 'No confirmed repeated defect pattern in current checked scope.'
            failure_point = 'none_confirmed'
            why_this_matters = 'Current scope does not provide evidence for a system-level repair action.'
        }
    }

    $hasP0Defect = ($P0Count -gt 0)
    $hasP1Defect = ($P1Count -gt 0)
    $primaryDefectFinding = if ($hasP0Defect) {
        Get-FirstOrNull -Collection @($ContextValidHighFindings | Where-Object { [string]$_.priority -eq 'P0' } | Select-Object -First 1)
    }
    elseif ($hasP1Defect) {
        Get-FirstOrNull -Collection @($ContextValidHighFindings | Where-Object { [string]$_.priority -eq 'P1' } | Select-Object -First 1)
    }
    else {
        Get-FirstOrNull -Collection $ContextValidHighFindings
    }
    $primaryLimitationFinding = Get-FirstOrNull -Collection $SortedLimitationFindings

    $selectedCluster = $null
    if (Test-HasItems -Collection $MicroClusters) {
        $priorityOrder = @{ BROKEN_ROUTE = 0; PROCESS_FIRST = 1; NO_VALUE_FIRST_SCREEN = 2; NO_ACTION_PATH = 3 }
        $selectedCluster = Get-FirstOrNull -Collection @(
            @($MicroClusters) |
            Sort-Object @{ Expression = {
                        $clusterType = [string]$_.cluster_type
                        if ($priorityOrder.ContainsKey($clusterType)) { [int]$priorityOrder[$clusterType] } else { 9 }
                    }
            }, @{ Expression = { -1 * [int]$_.surfaces_count } }, @{ Expression = { -1 * [int]$_.count } }
        )
        if ($null -ne $selectedCluster) {
            $clusterType = [string]$selectedCluster.cluster_type
            $clusterFindingsForQuality = @($ContextValidHighFindings | Where-Object { [string]$_.issue_type -eq $clusterType })
            $falsePositiveProneSurfaces = @('MEDIA_HOME', 'MEDIA_SECTION', 'ARTICLE', 'DIRECTORY')
            $nonProneClusterFindings = @($clusterFindingsForQuality | Where-Object { $falsePositiveProneSurfaces -notcontains [string]$_.surface_type })
            if ($nonProneClusterFindings.Count -eq 0 -and $clusterType -ne 'BROKEN_ROUTE') {
                $selectedCluster = $null
            }
        }
    }

    if ($null -ne $selectedCluster) {
        $clusterType = [string]$selectedCluster.cluster_type
        $systemTitle = switch ($clusterType) {
            'BROKEN_ROUTE' { 'Repeated route reachability failure across surfaces' }
            'PROCESS_FIRST' { 'Process-first framing appears before value across surfaces' }
            'NO_VALUE_FIRST_SCREEN' { 'Value proposition is missing on first screen across surfaces' }
            default { 'Action path is missing on first screen across surfaces' }
        }
        $systemDescriptionEn = switch ($clusterType) {
            'BROKEN_ROUTE' { 'Multiple surfaces fail to return a reachable route, so flow breaks before interaction.' }
            'PROCESS_FIRST' { 'Multiple surfaces start with process guidance before explaining value.' }
            'NO_VALUE_FIRST_SCREEN' { 'Multiple surfaces do not explain the value outcome on first screen.' }
            default { 'Multiple surfaces do not expose a clear next action on first screen.' }
        }
        $systemDescriptionRu = switch ($clusterType) {
            'BROKEN_ROUTE' { 'Несколько поверхностей не дают доступный маршрут, поэтому поток прерывается до взаимодействия.' }
            'PROCESS_FIRST' { 'На нескольких поверхностях сначала показывается процесс, а не ценность.' }
            'NO_VALUE_FIRST_SCREEN' { 'На нескольких поверхностях не объясняется ценность на первом экране.' }
            default { 'На нескольких поверхностях нет явного следующего действия на первом экране.' }
        }

        $clusterExamples = @(
            @($SortedFindings) |
            Where-Object { [string]$_.issue_type -eq $clusterType } |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    route = [string]$_.route
                    surface_type = Resolve-SurfaceType -SurfaceType ([string]$_.surface_type)
                    evidence = [string]$_.evidence_text
                }
            }
        )

        $clusterFirstFinding = Get-FirstOrNull -Collection @($SortedFindings | Where-Object { [string]$_.issue_type -eq $clusterType } | Select-Object -First 1)
        $clusterAction = if ($null -ne $clusterFirstFinding) { [string]$clusterFirstFinding.recommended_action } else { [string]$systemProblem.strongest_action }
        $clusterFirstExample = Get-FirstOrNull -Collection $clusterExamples
        $clusterEntrySurface = if ($null -ne $clusterFirstExample) { Resolve-SurfaceType -SurfaceType ([string]$clusterFirstExample.surface_type) } else { 'UNKNOWN' }

        $systemProblem = [ordered]@{
            problem_type = [string]$clusterType
            category = 'DEFECT'
            title = $systemTitle
            description = $systemDescriptionEn
            description_ru = $systemDescriptionRu
            affected_surfaces_count = [int]$selectedCluster.surfaces_count
            representative_examples = @($clusterExamples)
            strongest_action = [string]$clusterAction
            confidence = 'HIGH'
            source_cluster = [string]$clusterType
            interaction_explanation = [ordered]@{
                entry_surface = [string]$clusterEntrySurface
                expected_outcome = 'Surface should guide to value and next action without flow break.'
                actual_outcome = [string]$systemDescriptionEn
                failure_point = [string]$clusterType
                why_this_matters = 'Users lose clarity or progress before outcome is reached.'
            }
        }
    }
    elseif ($null -ne $primaryDefectFinding) {
        $singleExample = [ordered]@{
            route = [string]$primaryDefectFinding.route
            surface_type = Resolve-SurfaceType -SurfaceType ([string]$primaryDefectFinding.surface_type)
            evidence = [string]$primaryDefectFinding.evidence_text
        }
        $systemProblem = [ordered]@{
            problem_type = [string]$primaryDefectFinding.issue_type
            category = 'DEFECT'
            title = "Single strongest defect: $([string]$primaryDefectFinding.issue_type)"
            description = [string]$primaryDefectFinding.why_it_matters
            description_ru = [string]$primaryDefectFinding.why_it_matters
            affected_surfaces_count = 1
            representative_examples = @($singleExample)
            strongest_action = [string]$primaryDefectFinding.recommended_action
            confidence = [string]$primaryDefectFinding.confidence
            source_cluster = [string]$primaryDefectFinding.issue_type
            interaction_explanation = [ordered]@{
                entry_surface = Resolve-SurfaceType -SurfaceType ([string]$primaryDefectFinding.surface_type)
                expected_outcome = 'Surface should support a clear move to outcome.'
                actual_outcome = [string]$primaryDefectFinding.why_it_matters
                failure_point = [string]$primaryDefectFinding.issue_type
                why_this_matters = 'The strongest observed defect blocks reliable progression.'
            }
        }
    }
    elseif ($null -ne $primaryLimitationFinding) {
        $systemProblem = [ordered]@{
            problem_type = 'AUDIT_SCOPE_LIMIT'
            category = 'LIMITATION'
            title = 'Checked scope is limited by route budget'
            description = 'Coverage boundary prevented full surface verification in this run.'
            description_ru = 'Граница охвата не позволила проверить все поверхности в этом запуске.'
            affected_surfaces_count = 0
            representative_examples = @([ordered]@{ route = '_audit_scope'; surface_type = 'UNKNOWN'; evidence = [string]$primaryLimitationFinding.evidence_text })
            strongest_action = 'Expand route sample and rerun LINK mode for broader coverage.'
            confidence = [string]$AuditConfidence
            source_cluster = [string]$primaryLimitationFinding.issue_type
            interaction_explanation = [ordered]@{
                entry_surface = 'UNKNOWN'
                expected_outcome = 'All relevant surfaces are included in checked scope.'
                actual_outcome = 'Run coverage ended before all discovered routes were checked.'
                failure_point = 'coverage_boundary'
                why_this_matters = 'Boundary limits confidence and requires expanded coverage, not repair.'
            }
        }
    }

    return $systemProblem
}

function New-DecisionSummaryFromSystemProblem {
    param(
        [Parameter(Mandatory = $true)][object]$SystemProblem,
        [Parameter(Mandatory = $true)][string]$OwnershipMode,
        [Parameter(Mandatory = $true)][string]$AuditConfidence
    )

    $decisionIssueType = [string]$SystemProblem.category
    $primaryExample = Get-FirstOrNull -Collection @($SystemProblem.representative_examples)
    $primaryRoute = if ($decisionIssueType -eq 'DEFECT' -and $null -ne $primaryExample) { [string]$primaryExample.route } else { $null }

    return [ordered]@{
        issue_type = [string]$decisionIssueType
        primary_issue = [string]$SystemProblem.title
        primary_route = $primaryRoute
        priority = if ($decisionIssueType -eq 'DEFECT') { if ([string]$SystemProblem.problem_type -eq 'BROKEN_ROUTE') { 'P0' } else { 'P1' } } elseif ($decisionIssueType -eq 'LIMITATION') { 'P2' } else { 'NONE' }
        recommended_action = [string]$SystemProblem.strongest_action
        reasoning = [string]$SystemProblem.description
        ownership_mode = [string]$OwnershipMode
        audit_confidence = [string]$AuditConfidence
    }
}

function New-ActionSummaryFromDecision {
    param(
        [Parameter(Mandatory = $true)][object]$DecisionSummary,
        [Parameter(Mandatory = $true)][string]$DecisionIssueType,
        [Parameter(Mandatory = $true)][object]$SortedFindings,
        [Parameter(Mandatory = $true)][object]$SortedLimitationFindings,
        [Parameter(Mandatory = $true)][int]$DefectCount,
        [Parameter(Mandatory = $true)][int]$LimitationCount,
        [Parameter(Mandatory = $true)][string]$AuditConfidence
    )

    $actions = New-Object System.Collections.Generic.List[object]
    $null = $actions.Add([ordered]@{
            action = [string]$DecisionSummary.recommended_action
            why = [string]$DecisionSummary.reasoning
            priority = [string]$DecisionSummary.priority
        })

    if ($actions.Count -lt 3 -and $DecisionIssueType -eq 'DEFECT' -and @($SortedFindings).Count -gt 1) {
        foreach ($finding in @($SortedFindings | Select-Object -Skip 1)) {
            if ($actions.Count -ge 3) { break }
            $null = $actions.Add([ordered]@{
                    action = [string]$finding.recommended_action
                    why = [string]$finding.why_it_matters
                    priority = [string]$finding.priority
                })
        }
    }
    elseif ($actions.Count -lt 3 -and $DecisionIssueType -eq 'LIMITATION' -and @($SortedLimitationFindings).Count -gt 1) {
        foreach ($limitation in @($SortedLimitationFindings | Select-Object -Skip 1)) {
            if ($actions.Count -ge 3) { break }
            $null = $actions.Add([ordered]@{
                    action = [string]$limitation.recommended_action
                    why = [string]$limitation.why_it_matters
                    priority = [string]$limitation.priority
                })
        }
    }
    elseif ($actions.Count -lt 3 -and $DecisionIssueType -eq 'CLEAN' -and [string]$AuditConfidence -ne 'HIGH') {
        $null = $actions.Add([ordered]@{
                action = 'Expand route sample and rerun LINK mode for broader coverage.'
                why = 'Current checked scope may not represent full site behavior.'
                priority = 'P2'
            })
    }

    return [ordered]@{
        status = if ($DefectCount -gt 0) { 'FINDINGS_PRESENT' } elseif ($LimitationCount -gt 0) { 'LIMITATION_ONLY' } else { 'CLEAN' }
        finding_count = [int]$DefectCount
        limitation_count = [int]$LimitationCount
        actions = @($actions.ToArray())
        reason = if ($DefectCount -gt 0) { 'deterministic_findings_generated_from_link_truth_artifacts' } elseif ($LimitationCount -gt 0) { 'audit_limited_by_route_sampling_budget' } else { 'no_material_findings_in_sampled_scope' }
    }
}

function New-HumanReportPayloads {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$DecisionIssueType,
        [Parameter(Mandatory = $true)][string]$OverallVerdict,
        [Parameter(Mandatory = $true)][int]$RoutesChecked,
        [Parameter(Mandatory = $true)][int]$DefectCount,
        [Parameter(Mandatory = $true)][object]$SortedFindings
    )

    $dominantSurfaceType = Resolve-DominantSurface -PageVerdicts $Report.page_verdicts
    $dominantSurfaceExpectation = Get-SurfaceExpectation -SurfaceType $dominantSurfaceType

    $mainProblemEn = if ($DecisionIssueType -eq 'CLEAN') { 'No confirmed system-level defect was established in the checked scope.' } else { [string]$Report.system_problem.title }
    $mainProblemRu = if ($DecisionIssueType -eq 'CLEAN') { 'Подтверждённый системный дефект в проверенном объёме не установлен.' } else { [string]$Report.system_problem.description_ru }

    $limitationsCommon = New-Object System.Collections.Generic.List[string]
    if ($DecisionIssueType -eq 'LIMITATION') {
        $limitationsCommon.Add('Coverage boundary: not all discovered routes were checked in this run.')
    }
    elseif ([string]$Report.audit_confidence -ne 'HIGH' -and [int]$Report.run_budget.overflow_routes -gt 0) {
        $limitationsCommon.Add("Checked scope is partial: $([int]$Report.run_budget.overflow_routes) discovered routes were outside current route budget.")
    }

    $supportingExamples = Resolve-RepresentativeExamples -Examples $Report.system_problem.representative_examples -MaxItems 3 -FallbackEvidence 'No high-confidence supporting examples in checked scope.'
    $supportingLinesEn = @($supportingExamples | ForEach-Object { "$([string]$_.route) ($([string](Resolve-SurfaceType -SurfaceType ([string]$_.surface_type))): $([string]$_.evidence))" })
    $supportingLinesRu = @($supportingExamples | ForEach-Object { "$([string]$_.route) ($([string](Resolve-SurfaceType -SurfaceType ([string]$_.surface_type))): $([string]$_.evidence))" })

    $impactLinesEn = if ($DecisionIssueType -eq 'DEFECT') {
        @('Users face repeated friction before reaching the expected outcome.', 'Critical surfaces lose consistency, reducing decision confidence.', 'The same failure pattern scales across multiple surfaces.')
    }
    elseif ($DecisionIssueType -eq 'LIMITATION') {
        @('Coverage is incomplete, so defect absence cannot be confirmed for full scope.')
    }
    else {
        @('No confirmed system-level defects were identified in the checked scope.')
    }
    $impactLinesRu = if ($DecisionIssueType -eq 'DEFECT') {
        @('Пользователь сталкивается с повторяющимся барьером до результата.', 'Ключевые поверхности работают несогласованно и снижают доверие к выбору.', 'Один и тот же сбой повторяется на нескольких поверхностях.')
    }
    elseif ($DecisionIssueType -eq 'LIMITATION') {
        @('Охват неполный, поэтому отсутствие дефектов нельзя подтвердить для всего объёма.')
    }
    else {
        @('Подтверждённых системных дефектов в проверенном объёме не выявлено.')
    }

    $supportingActions = New-Object System.Collections.Generic.List[string]
    if ($DecisionIssueType -eq 'DEFECT') {
        foreach ($finding in @($SortedFindings | Select-Object -First 3)) {
            if ([string]$finding.recommended_action -ne [string]$Report.system_problem.strongest_action -and $supportingActions.Count -lt 2) {
                $supportingActions.Add([string]$finding.recommended_action)
            }
        }
    }
    elseif ($DecisionIssueType -eq 'LIMITATION') {
        $supportingActions.Add('Validate uncovered routes in a controlled follow-up run.')
    }

    $actionsEn = New-Object System.Collections.Generic.List[string]
    $actionsEn.Add([string]$Report.system_problem.strongest_action)
    foreach ($a in $supportingActions | Select-Object -First 2) { $actionsEn.Add([string]$a) }

    $actionsRu = New-Object System.Collections.Generic.List[string]
    $actionsRu.Add([string]$Report.system_problem.strongest_action)
    foreach ($a in $supportingActions | Select-Object -First 2) { $actionsRu.Add([string]$a) }

    return [ordered]@{
        en = [ordered]@{
            executive_lines = @("Verdict: $OverallVerdict.", "Confidence: $([string]$Report.audit_confidence).", "Surface context: $([string]$dominantSurfaceExpectation.context_note_en)", "Main action: $([string]$Report.system_problem.strongest_action)")
            main_problem = $mainProblemEn
            impact_lines = @($impactLinesEn | Select-Object -First 3)
            actions_lines = @($actionsEn | Select-Object -First 3)
            evidence_lines = @($supportingLinesEn | Select-Object -First 3)
            limitations_lines = @($limitationsCommon | Select-Object -First 1)
            include_limitations = ($limitationsCommon.Count -gt 0)
            snapshot_rows = @([ordered]@{ label = 'Pages checked'; value = [string]$RoutesChecked }, [ordered]@{ label = 'High-confidence findings'; value = [string]$DefectCount }, [ordered]@{ label = 'Primary category'; value = [string]$DecisionIssueType }, [ordered]@{ label = 'Confidence'; value = [string]$Report.audit_confidence })
        }
        ru = [ordered]@{
            executive_lines = @("Вердикт: $OverallVerdict.", "Уверенность: $([string]$Report.audit_confidence).", "Контекст поверхности: $([string]$dominantSurfaceExpectation.context_note_ru)", "Главное действие: $([string]$Report.system_problem.strongest_action)")
            main_problem = [string]$mainProblemRu
            impact_lines = @($impactLinesRu | Select-Object -First 3)
            actions_lines = @($actionsRu | Select-Object -First 3)
            evidence_lines = @($supportingLinesRu | Select-Object -First 3)
            limitations_lines = @($limitationsCommon | Select-Object -First 1)
            include_limitations = ($limitationsCommon.Count -gt 0)
            snapshot_rows = @([ordered]@{ label = 'Проверено страниц'; value = [string]$RoutesChecked }, [ordered]@{ label = 'Находки высокой уверенности'; value = [string]$DefectCount }, [ordered]@{ label = 'Категория'; value = [string]$DecisionIssueType }, [ordered]@{ label = 'Уверенность'; value = [string]$Report.audit_confidence })
        }
    }
}

function Ensure-OperatorMemoryBridgeRequiredFields {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $false)][int]$LimitationCount = 0
    )

    if ($null -eq $Report.operator_memory_bridge) {
        $Report | Add-Member -NotePropertyName operator_memory_bridge -NotePropertyValue ([ordered]@{}) -Force
    }

    $runStatus = [string]$Report.status
    $auditConfidence = [string]$Report.audit_confidence
    $statusDetail = if ($runStatus -eq 'FAIL') {
        'FAIL'
    }
    elseif ($runStatus -eq 'PASS') {
        if ($auditConfidence -eq 'LOW') { 'PASS_WITH_LIMITS' } else { 'PASS' }
    }
    else {
        'FAIL'
    }

    $runId = if ($null -ne $Report.PSObject.Properties['run_id']) { [string]$Report.run_id } else { '' }
    $nextFileToInspect = if (-not [string]::IsNullOrWhiteSpace($runId)) { "agents/site_auditor_v2/output/$runId/RUN_REPORT.json" } else { 'RUN_REPORT.json' }
    $recommendedAction = if ($null -ne $Report.PSObject.Properties['decision_summary'] -and $null -ne $Report.decision_summary -and -not [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.recommended_action)) {
        [string]$Report.decision_summary.recommended_action
    }
    else {
        "Inspect $nextFileToInspect to verify report consistency and operator-control details."
    }
    $reasonToInspect = if ($statusDetail -eq 'PASS_WITH_LIMITS') {
        if ($LimitationCount -gt 0) {
            "PASS_WITH_LIMITS due to $LimitationCount documented limitation(s); verify artifacts and constraints in RUN_REPORT."
        }
        else {
            'PASS_WITH_LIMITS due to low confidence or incomplete evidence; verify artifacts and constraints in RUN_REPORT.'
        }
    }
    elseif ($statusDetail -eq 'FAIL') {
        'FAIL status detected; inspect RUN_REPORT artifacts to confirm root causes and required remediation.'
    }
    else {
        'PASS status requires artifact verification to ensure no hidden limitations remain in RUN_REPORT.'
    }

    $forbiddenNextSteps = @(
        'Do not weaken or bypass the consistency lock.',
        'Do not edit workflows, entrypoints, or runtime audit logic for this fix.'
    )

    $Report.operator_memory_bridge | Add-Member -NotePropertyName status_detail -NotePropertyValue $statusDetail -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName current_execution_mode -NotePropertyValue ($(if (-not [string]::IsNullOrWhiteSpace([string]$Report.mode)) { [string]$Report.mode } else { 'LINK' })) -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName current_layer -NotePropertyValue 'REPORT_LAYER' -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName layer_owner_file -NotePropertyValue 'agents/site_auditor_v2/modules/report_layer.ps1' -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName next_file_to_inspect -NotePropertyValue $nextFileToInspect -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName reason_to_inspect -NotePropertyValue $reasonToInspect -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName one_next_step -NotePropertyValue $recommendedAction -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName forbidden_next_steps -NotePropertyValue $forbiddenNextSteps -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName tool_recommendation -NotePropertyValue 'CodeSpace for verification; Codex only for targeted patch' -Force
    $Report.operator_memory_bridge | Add-Member -NotePropertyName tool_hint -NotePropertyValue 'CodeSpace for verification; Codex only for targeted patch' -Force
}

function Test-ReportConsistencyLock {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][hashtable]$FinalActionSummary,
        [Parameter(Mandatory = $true)][object]$ReportPayloadRu,
        [Parameter(Mandatory = $true)][object]$ReportPayloadEn,
        [Parameter(Mandatory = $true)][string]$DecisionIssueType,
        [Parameter(Mandatory = $true)][int]$DefectCount,
        [Parameter(Mandatory = $true)][int]$LimitationCount
    )

    Ensure-OperatorMemoryBridgeRequiredFields -Report $Report -LimitationCount $LimitationCount

    $firstActionSummaryAction = Get-FirstOrNull -Collection @($FinalActionSummary.actions)
    $firstRuActionLine = Get-FirstOrNull -Collection @($ReportPayloadRu.actions_lines)
    $firstEnActionLine = Get-FirstOrNull -Collection @($ReportPayloadEn.actions_lines)
    $statusLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Report.status_label)) { [string]$Report.status_label } else { [string]$Report.status }
    $operatorBridge = $Report.operator_memory_bridge
    $statusDetail = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['status_detail']) { [string]$operatorBridge.status_detail } else { '' }
    $currentExecutionMode = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['current_execution_mode']) { [string]$operatorBridge.current_execution_mode } else { '' }
    $currentLayer = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['current_layer']) { [string]$operatorBridge.current_layer } else { '' }
    $layerOwnerFile = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['layer_owner_file']) { [string]$operatorBridge.layer_owner_file } else { '' }
    $nextFileToInspect = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['next_file_to_inspect']) { [string]$operatorBridge.next_file_to_inspect } else { '' }
    $reasonToInspect = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['reason_to_inspect']) { [string]$operatorBridge.reason_to_inspect } else { '' }
    $oneNextStep = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['one_next_step']) { [string]$operatorBridge.one_next_step } else { '' }
    $forbiddenNextSteps = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['forbidden_next_steps']) { @($operatorBridge.forbidden_next_steps) } else { @() }
    $toolRecommendation = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['tool_recommendation']) { [string]$operatorBridge.tool_recommendation } else { '' }
    $toolHint = if ($null -ne $operatorBridge -and $null -ne $operatorBridge.PSObject.Properties['tool_hint']) { [string]$operatorBridge.tool_hint } else { '' }
    if ($null -eq $firstActionSummaryAction -or [string]$firstActionSummaryAction.action -ne [string]$Report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: ACTION_SUMMARY first action mismatch.' }
    if ($null -eq $firstRuActionLine -or [string]$firstRuActionLine -ne [string]$Report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: RU main action mismatch.' }
    if ($null -eq $firstEnActionLine -or [string]$firstEnActionLine -ne [string]$Report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: EN main action mismatch.' }
    if ([string]::IsNullOrWhiteSpace([string]$Report.decision_summary.issue_type) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.primary_issue) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.priority) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.recommended_action) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.reasoning) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.ownership_mode) -or [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.audit_confidence)) { throw 'CONSISTENCY_LOCK_FAILED: decision_summary has null critical fields.' }
    if ([string]$Report.decision_summary.issue_type -eq 'DEFECT' -and [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.primary_route)) { throw 'CONSISTENCY_LOCK_FAILED: defect decision missing primary_route.' }
    if ([string]$Report.decision_summary.issue_type -ne 'DEFECT' -and $null -ne $Report.decision_summary.primary_route -and -not [string]::IsNullOrWhiteSpace([string]$Report.decision_summary.primary_route)) { throw 'CONSISTENCY_LOCK_FAILED: non-defect decision must not set primary_route.' }
    if ($DecisionIssueType -eq 'LIMITATION' -and $DefectCount -gt 0) { throw 'CONSISTENCY_LOCK_FAILED: limitation classified despite defect findings.' }
    if ($DecisionIssueType -eq 'DEFECT' -and $DefectCount -eq 0) { throw 'CONSISTENCY_LOCK_FAILED: defect classified without defect findings.' }
    if ($DecisionIssueType -eq 'CLEAN' -and ($DefectCount -gt 0 -or $LimitationCount -gt 0)) { throw 'CONSISTENCY_LOCK_FAILED: clean classified despite findings.' }
    if ($DecisionIssueType -eq 'LIMITATION' -and [string]$ReportPayloadEn.main_problem -match 'defect') { throw 'CONSISTENCY_LOCK_FAILED: limitation presented as defect in EN report.' }
    if ($DecisionIssueType -eq 'LIMITATION' -and [string]$ReportPayloadRu.main_problem -match 'дефект') { throw 'CONSISTENCY_LOCK_FAILED: limitation presented as defect in RU report.' }
    if (@($ReportPayloadEn.evidence_lines).Count -gt 3 -or @($ReportPayloadRu.evidence_lines).Count -gt 3) { throw 'CONSISTENCY_LOCK_FAILED: too many supporting examples.' }
    if (@($ReportPayloadEn.actions_lines).Count -gt 3 -or @($ReportPayloadRu.actions_lines).Count -gt 3) { throw 'CONSISTENCY_LOCK_FAILED: too many action bullets.' }
    if ([string]$Report.system_problem.strongest_action -ne [string]$Report.decision_summary.recommended_action -or [string]$Report.system_problem.strongest_action -ne [string]$Report.next_strongest_move -or [string]$Report.system_problem.strongest_action -ne [string]$firstActionSummaryAction.action -or [string]$Report.system_problem.strongest_action -ne [string]$firstEnActionLine -or [string]$Report.system_problem.strongest_action -ne [string]$firstRuActionLine) { throw 'CONSISTENCY_LOCK_FAILED: strongest_action chain mismatch.' }
    if ([string]::IsNullOrWhiteSpace($statusDetail)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.status_detail is required.' }
    if ([string]::IsNullOrWhiteSpace($currentExecutionMode)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.current_execution_mode is required.' }
    if ([string]::IsNullOrWhiteSpace($currentLayer)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.current_layer is required.' }
    if ([string]::IsNullOrWhiteSpace($layerOwnerFile)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.layer_owner_file is required.' }
    if ([string]::IsNullOrWhiteSpace($nextFileToInspect)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.next_file_to_inspect is required.' }
    if ([string]::IsNullOrWhiteSpace($reasonToInspect)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.reason_to_inspect is required.' }
    if ([string]::IsNullOrWhiteSpace($oneNextStep)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.one_next_step is required.' }
    if (@($forbiddenNextSteps).Count -eq 0) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.forbidden_next_steps is required.' }
    if ([string]::IsNullOrWhiteSpace($toolRecommendation) -and [string]::IsNullOrWhiteSpace($toolHint)) { throw 'CONSISTENCY_LOCK_FAILED: operator_memory_bridge.tool_recommendation or tool_hint is required.' }
    if ([string]$statusLabel -eq 'PASS_WITH_LIMITS' -and [string]::IsNullOrWhiteSpace([string]$Report.confidence_reason)) { throw 'CONSISTENCY_LOCK_FAILED: PASS_WITH_LIMITS must include confidence_reason limitation.' }
}
