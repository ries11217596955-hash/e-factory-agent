function Get-SiteAuditorV3SessionUtcNow {
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-SiteAuditorV3SeverityCounts {
    param([Parameter(Mandatory)][object[]]$Items)

    $counts = [ordered]@{
        critical = 0
        high = 0
        medium = 0
        low = 0
        info = 0
        unknown = 0
    }

    foreach ($item in @($Items)) {
        $raw = $null
        if ($item -and $item.ContainsKey("type")) { $raw = [string]$item.type }
        elseif ($item -and $item.ContainsKey("priority")) { $raw = [string]$item.priority }

        $key = if ([string]::IsNullOrWhiteSpace($raw)) { "unknown" } else { $raw.Trim().ToLowerInvariant() }
        if ($counts.Contains($key)) { $counts[$key] = [int]$counts[$key] + 1 }
        else { $counts.unknown = [int]$counts.unknown + 1 }
    }

    return $counts
}

function Get-SiteAuditorV3PriorityRank {
    param([string]$Priority)

    $normalizedPriority = ""
    if ($null -ne $Priority) { $normalizedPriority = [string]$Priority }
    switch ($normalizedPriority.Trim().ToLowerInvariant()) {
        "critical" { return 0 }
        "high" { return 1 }
        "medium" { return 2 }
        "low" { return 3 }
        "info" { return 4 }
        default { return 5 }
    }
}

function Get-SiteAuditorV3TopFindingGroups {
    param([Parameter(Mandatory)][object[]]$Findings)

    $groups = @($Findings | Group-Object -Property code | Sort-Object @{ Expression = { -1 * [int]$_.Count }; Ascending = $true }, @{ Expression = { [string]$_.Name }; Ascending = $true })
    $result = @()

    foreach ($group in $groups) {
        $items = @($group.Group)
        if ($items.Count -eq 0) { continue }

        $first = $items[0]
        $routeIds = @($items | ForEach-Object {
            if ($_ -and $_.ContainsKey("route_id")) { [string]$_.route_id }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

        $messages = @($items | ForEach-Object {
            if ($_ -and $_.ContainsKey("message")) { [string]$_.message }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

        $result += [ordered]@{
            finding_code = [string]$group.Name
            severity = if ($first -and $first.ContainsKey("type")) { [string]$first.type } else { "unknown" }
            count = [int]$group.Count
            affected_route_count = $routeIds.Count
            affected_route_ids = @($routeIds)
            message_samples = @($messages | Select-Object -First 3)
        }
    }

    return @($result)
}

function Get-SiteAuditorV3ActionGroups {
    param([Parameter(Mandatory)][object[]]$Actions)

    $groups = @($Actions | Group-Object -Property action_id)
    $result = @()

    foreach ($group in $groups) {
        $items = @($group.Group)
        if ($items.Count -eq 0) { continue }

        $first = $items[0]
        $priorities = @($items | ForEach-Object {
            if ($_ -and $_.ContainsKey("priority")) { [string]$_.priority }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $winningPriority = "unknown"
        if ($priorities.Count -gt 0) {
            $winningPriority = @($priorities | Sort-Object { Get-SiteAuditorV3PriorityRank -Priority $_ } | Select-Object -First 1)[0]
        }

        $result += [ordered]@{
            action_id = [string]$group.Name
            priority = [string]$winningPriority
            count = [int]$group.Count
            action = if ($first -and $first.ContainsKey("action")) { [string]$first.action } else { $null }
            why = if ($first -and $first.ContainsKey("why")) { [string]$first.why } else { $null }
            target_module = if ($first -and $first.ContainsKey("target_module")) { [string]$first.target_module } else { $null }
            acceptance = if ($first -and $first.ContainsKey("acceptance")) { [string]$first.acceptance } else { $null }
        }
    }

    return @($result | Sort-Object @{ Expression = { Get-SiteAuditorV3PriorityRank -Priority $_.priority }; Ascending = $true }, @{ Expression = { -1 * [int]$_.count }; Ascending = $true }, @{ Expression = { $_.action_id }; Ascending = $true })
}

function New-SiteAuditorV3ReportStream {
    param(
        [Parameter(Mandatory)][string]$StreamId,
        [Parameter(Mandatory)][string]$StreamType,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$RecordsCount,
        [Parameter(Mandatory)]$AggregateMetrics,
        [Parameter(Mandatory)][object[]]$TopFindings,
        [Parameter(Mandatory)]$SeverityCounts,
        [Parameter(Mandatory)][string[]]$AggregationNotes
    )

    return [ordered]@{
        stream_id = $StreamId
        stream_type = $StreamType
        schema_version = "1.0.0"
        status = "AGGREGATED"
        source = $Source
        records_count = $RecordsCount
        severity_counts = $SeverityCounts
        aggregate_metrics = $AggregateMetrics
        top_findings = @($TopFindings)
        aggregation_notes = @($AggregationNotes)
    }
}

function New-SiteAuditorV3SessionFinalization {
    param(
        [Parameter(Mandatory)]$Ledger,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunRoot
    )

    $findings = @($Ledger.cumulative_findings)
    $actions = @($Ledger.cumulative_finding_actions)
    $batchHistory = @($Ledger.batch_history)
    $findingSeverityCounts = Get-SiteAuditorV3SeverityCounts -Items $findings
    $actionSeverityCounts = Get-SiteAuditorV3SeverityCounts -Items $actions
    $topFindingGroups = Get-SiteAuditorV3TopFindingGroups -Findings $findings
    $actionGroups = Get-SiteAuditorV3ActionGroups -Actions $actions

    $coverageStream = New-SiteAuditorV3ReportStream `
        -StreamId "coverage_truth" `
        -StreamType "session_coverage" `
        -Source "AUDIT_SESSION_LEDGER.json" `
        -RecordsCount ([int]$Ledger.inventory_url_count) `
        -AggregateMetrics ([ordered]@{
            inventory_url_count = [int]$Ledger.inventory_url_count
            audited_url_count = @($Ledger.audited_urls).Count
            pending_url_count = @($Ledger.pending_urls).Count
            failed_url_count = @($Ledger.failed_urls).Count
            coverage_percent = [double]$Ledger.coverage_percent
        }) `
        -TopFindings @() `
        -SeverityCounts ([ordered]@{ critical = 0; high = 0; medium = 0; low = 0; info = 0; unknown = 0 }) `
        -AggregationNotes @("Coverage stream defines whether finalization is allowed.")

    $findingsStream = New-SiteAuditorV3ReportStream `
        -StreamId "cumulative_findings" `
        -StreamType "finding_inventory" `
        -Source "AUDIT_SESSION_LEDGER.json:cumulative_findings" `
        -RecordsCount $findings.Count `
        -AggregateMetrics ([ordered]@{
            unique_finding_codes = @($topFindingGroups).Count
            affected_route_count = @($topFindingGroups | ForEach-Object { @($_.affected_route_ids) } | ForEach-Object { $_ } | Select-Object -Unique).Count
        }) `
        -TopFindings @($topFindingGroups | Select-Object -First 10) `
        -SeverityCounts $findingSeverityCounts `
        -AggregationNotes @("Findings are cumulative across every completed batch in the audit session.")

    $actionsStream = New-SiteAuditorV3ReportStream `
        -StreamId "remediation_actions" `
        -StreamType "action_inventory" `
        -Source "AUDIT_SESSION_LEDGER.json:cumulative_finding_actions" `
        -RecordsCount $actions.Count `
        -AggregateMetrics ([ordered]@{
            unique_action_ids = @($actionGroups).Count
            priority_clusters = @($actionGroups | Group-Object -Property priority | ForEach-Object {
                [ordered]@{ priority = [string]$_.Name; count = [int]$_.Count }
            })
        }) `
        -TopFindings @($actionGroups | Select-Object -First 10) `
        -SeverityCounts $actionSeverityCounts `
        -AggregationNotes @("Action stream is deduplicated into repair clusters without losing occurrence counts.")

    $batchStream = New-SiteAuditorV3ReportStream `
        -StreamId "batch_execution_history" `
        -StreamType "run_chain" `
        -Source "AUDIT_SESSION_LEDGER.json:batch_history" `
        -RecordsCount $batchHistory.Count `
        -AggregateMetrics ([ordered]@{
            completed_batch_count = $batchHistory.Count
            run_ids = @($batchHistory | ForEach-Object { [string]$_.run_id })
            audit_actions = @($batchHistory | ForEach-Object { [string]$_.audit_action } | Select-Object -Unique)
            last_run_id = [string]$Ledger.last_completed_run_id
        }) `
        -TopFindings @() `
        -SeverityCounts ([ordered]@{ critical = 0; high = 0; medium = 0; low = 0; info = 0; unknown = 0 }) `
        -AggregationNotes @("Batch history preserves the exact session run chain that produced the final verdict.")

    $supportedStreamIds = @(
        "coverage_truth",
        "cumulative_findings",
        "remediation_actions",
        "batch_execution_history"
    )
    $declaredFutureStreams = @()
    if ($Ledger.ContainsKey("future_report_streams")) {
        $declaredFutureStreams = @($Ledger.future_report_streams | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    $unaggregatedStreams = @($declaredFutureStreams | Where-Object { $supportedStreamIds -notcontains $_ })

    $systemicFindingGroups = @($topFindingGroups | Where-Object { [int]$_.count -ge 2 })
    $dominantActionGroups = @($actionGroups | Select-Object -First 5)
    $highestSeverity = "clean"
    if ([int]$findingSeverityCounts.critical -gt 0) { $highestSeverity = "critical" }
    elseif ([int]$findingSeverityCounts.high -gt 0) { $highestSeverity = "high" }
    elseif ([int]$findingSeverityCounts.medium -gt 0) { $highestSeverity = "medium" }
    elseif ([int]$findingSeverityCounts.low -gt 0) { $highestSeverity = "low" }

    $finalVerdict = "CLEAN"
    $decisionReason = "No cumulative findings require repair."
    if ([int]$findingSeverityCounts.critical -gt 0 -or [int]$findingSeverityCounts.high -gt 0) {
        $finalVerdict = "REPAIR_REQUIRED"
        $decisionReason = "Critical/high cumulative findings exist across the completed session."
    } elseif ([int]$findingSeverityCounts.medium -gt 0) {
        $finalVerdict = "REVIEW_AND_REPAIR"
        $decisionReason = "The session is complete, but repeated medium findings require a repair plan."
    } elseif ([int]$findingSeverityCounts.low -gt 0) {
        $finalVerdict = "REVIEW"
        $decisionReason = "Only low-severity findings remain after full coverage."
    }

    $oneNextAction = if ($dominantActionGroups.Count -gt 0) {
        [ordered]@{
            action_id = [string]$dominantActionGroups[0].action_id
            action = [string]$dominantActionGroups[0].action
            priority = [string]$dominantActionGroups[0].priority
            why = [string]$dominantActionGroups[0].why
            target_module = [string]$dominantActionGroups[0].target_module
            acceptance = [string]$dominantActionGroups[0].acceptance
        }
    } else {
        [ordered]@{
            action_id = "review_final_operator_report"
            action = "Review the final operator report and keep the completed audit as baseline truth."
            priority = "info"
            why = "No repair action was synthesized from the completed audit session."
            target_module = "operator"
            acceptance = "FINAL_OPERATOR_REPORT.md reviewed"
        }
    }

    $finalizedAt = Get-SiteAuditorV3SessionUtcNow

    $sessionAggregate = [ordered]@{
        schema_version = "1.0.0"
        artifact = "SESSION_AGGREGATE"
        finalization_status = "FINALIZED"
        finalized_at_utc = $finalizedAt
        session_identity = [ordered]@{
            session_id = [string]$Ledger.session_id
            target_url = if ($Ledger.ContainsKey("target_url")) { [string]$Ledger.target_url } else { $null }
            base_url = [string]$Ledger.base_url
            finalizing_run_id = $RunId
            last_completed_run_id = [string]$Ledger.last_completed_run_id
        }
        coverage_truth = [ordered]@{
            total_inventory_count = [int]$Ledger.inventory_url_count
            total_audited_count = @($Ledger.audited_urls).Count
            total_pending_count = @($Ledger.pending_urls).Count
            failed_url_count = @($Ledger.failed_urls).Count
            coverage_percent = [double]$Ledger.coverage_percent
            coverage_gate = if (@($Ledger.pending_urls).Count -eq 0) { "PASS" } else { "FAIL" }
        }
        run_chain_truth = [ordered]@{
            batches_completed = $batchHistory.Count
            completed_batch_ids = @($Ledger.completed_batch_ids)
            run_ids = @($batchHistory | ForEach-Object { [string]$_.run_id })
            audit_actions = @($batchHistory | ForEach-Object { [string]$_.audit_action })
        }
        report_streams = @($coverageStream, $findingsStream, $actionsStream, $batchStream)
        aggregation_completeness = [ordered]@{
            supported_stream_ids = $supportedStreamIds
            declared_future_stream_ids = @($declaredFutureStreams)
            unaggregated_stream_ids = @($unaggregatedStreams)
            completeness_status = if ($unaggregatedStreams.Count -eq 0) { "COMPLETE" } else { "COMPLETE_WITH_UNAGGREGATED_FUTURE_STREAMS" }
            notes = if ($unaggregatedStreams.Count -eq 0) {
                @("All currently declared report streams were aggregated.")
            } else {
                @("Future stream identifiers were declared in the ledger but no registered aggregator exists yet.")
            }
        }
        cross_stream_synthesis = [ordered]@{
            highest_severity = $highestSeverity
            systemic_finding_group_count = $systemicFindingGroups.Count
            systemic_finding_groups = @($systemicFindingGroups | Select-Object -First 10)
            dominant_action_groups = @($dominantActionGroups)
            final_problem_shape = if ($systemicFindingGroups.Count -gt 0) { "systemic" } elseif ($topFindingGroups.Count -gt 0) { "localized_or_sparse" } else { "clean" }
        }
        final_decision = [ordered]@{
            verdict = $finalVerdict
            reason = $decisionReason
            one_next_action = $oneNextAction
        }
    }

    $findingsIndex = [ordered]@{
        schema_version = "1.0.0"
        artifact = "FINAL_FINDINGS_INDEX"
        session_id = [string]$Ledger.session_id
        findings_count = $findings.Count
        action_count = $actions.Count
        finding_groups = @($topFindingGroups)
        action_groups = @($actionGroups)
    }

    $finalActionPlan = [ordered]@{
        schema_version = "1.0.0"
        artifact = "FINAL_ACTION_PLAN"
        session_id = [string]$Ledger.session_id
        verdict = $finalVerdict
        action_count = @($actionGroups).Count
        actions = @($actionGroups)
        one_next_action = $oneNextAction
        repair_order_rule = "priority desc by severity, then occurrence count desc, then action_id asc"
    }

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add("# FINAL_OPERATOR_REPORT")
    $reportLines.Add("")
    $reportLines.Add("## Session")
    $reportLines.Add("- session_id: $($Ledger.session_id)")
    $reportLines.Add("- target_url: $($Ledger.target_url)")
    $reportLines.Add("- finalized_at_utc: $finalizedAt")
    $reportLines.Add("- batches_completed: $($batchHistory.Count)")
    $reportLines.Add("")
    $reportLines.Add("## Coverage truth")
    $reportLines.Add("- inventory: $([int]$Ledger.inventory_url_count)")
    $reportLines.Add("- audited: $(@($Ledger.audited_urls).Count)")
    $reportLines.Add("- pending: $(@($Ledger.pending_urls).Count)")
    $reportLines.Add("- coverage_percent: $([double]$Ledger.coverage_percent)")
    $reportLines.Add("")
    $reportLines.Add("## Final verdict")
    $reportLines.Add("- verdict: $finalVerdict")
    $reportLines.Add("- reason: $decisionReason")
    $reportLines.Add("")
    $reportLines.Add("## Strongest repair priorities")
    if ($dominantActionGroups.Count -eq 0) {
        $reportLines.Add("- No synthesized repair action remains; preserve this artifact as completed-session baseline.")
    } else {
        foreach ($actionGroup in @($dominantActionGroups)) {
            $reportLines.Add("- [$($actionGroup.priority)] $($actionGroup.action_id) × $($actionGroup.count): $($actionGroup.action)")
        }
    }
    $reportLines.Add("")
    $reportLines.Add("## Dominant findings")
    if ($topFindingGroups.Count -eq 0) {
        $reportLines.Add("- No cumulative findings were recorded.")
    } else {
        foreach ($findingGroup in @($topFindingGroups | Select-Object -First 10)) {
            $reportLines.Add("- [$($findingGroup.severity)] $($findingGroup.finding_code) × $($findingGroup.count) across $($findingGroup.affected_route_count) route(s)")
        }
    }
    $reportLines.Add("")
    $reportLines.Add("## Report streams included")
    foreach ($stream in @($sessionAggregate.report_streams)) {
        $reportLines.Add("- $($stream.stream_id): $($stream.records_count) record(s), status=$($stream.status)")
    }
    $reportLines.Add("")
    $reportLines.Add("## Aggregation completeness")
    $reportLines.Add("- status: $($sessionAggregate.aggregation_completeness.completeness_status)")
    $reportLines.Add("- unaggregated_streams: $(@($sessionAggregate.aggregation_completeness.unaggregated_stream_ids) -join ', ')")
    $reportLines.Add("")
    $reportLines.Add("## One next action")
    $reportLines.Add("- action_id: $($oneNextAction.action_id)")
    $reportLines.Add("- action: $($oneNextAction.action)")
    $reportLines.Add("- why: $($oneNextAction.why)")
    $reportLines.Add("- acceptance: $($oneNextAction.acceptance)")

    return [ordered]@{
        finalized_at_utc = $finalizedAt
        session_aggregate = $sessionAggregate
        findings_index = $findingsIndex
        final_action_plan = $finalActionPlan
        final_operator_report = ($reportLines -join [Environment]::NewLine)
        artifact_paths = [ordered]@{
            session_aggregate = Join-Path $RunRoot "SESSION_AGGREGATE.json"
            final_operator_report = Join-Path $RunRoot "FINAL_OPERATOR_REPORT.md"
            final_action_plan = Join-Path $RunRoot "FINAL_ACTION_PLAN.json"
            final_findings_index = Join-Path $RunRoot "FINAL_FINDINGS_INDEX.json"
        }
    }
}
