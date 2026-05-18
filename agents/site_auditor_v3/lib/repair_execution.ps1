function Get-SiteAuditorV3RepairUtcNow {
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-SiteAuditorV3RepairExecutionClass {
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)]$Contract
    )

    $targetModule = if ($Action -and $Action.ContainsKey("target_module")) { [string]$Action.target_module } else { "" }
    $agentModules = @($Contract.classification_policy.agent_internal_target_modules | ForEach-Object { [string]$_ })
    $targetGuidanceModules = @($Contract.classification_policy.target_guidance_modules | ForEach-Object { [string]$_ })

    if ($agentModules -contains $targetModule) {
        return "AGENT_REPAIR_CANDIDATE"
    }
    if ($targetGuidanceModules -contains $targetModule) {
        return "TARGET_REPAIR_GUIDANCE"
    }
    return "OPERATOR_REVIEW"
}

function Get-SiteAuditorV3RepairExecutionDisposition {
    param([Parameter(Mandatory)][string]$ExecutionClass)

    switch ($ExecutionClass) {
        "AGENT_REPAIR_CANDIDATE" { return "PREPARE_INTERNAL_REPAIR_TASK" }
        "TARGET_REPAIR_GUIDANCE" { return "HAND_OFF_GUIDANCE_ONLY" }
        default { return "REQUIRE_OPERATOR_REVIEW" }
    }
}

function Get-SiteAuditorV3RepairPriorityRank {
    param([string]$Priority)

    $normalized = if ($null -eq $Priority) { "" } else { [string]$Priority }
    switch ($normalized.Trim().ToLowerInvariant()) {
        "critical" { return 0 }
        "high" { return 1 }
        "medium" { return 2 }
        "low" { return 3 }
        "info" { return 4 }
        default { return 5 }
    }
}

function New-SiteAuditorV3RepairExecutionPlan {
    param(
        [Parameter(Mandatory)]$FinalActionPlan,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)][string]$RunReportRelativePath
    )

    $actions = @($FinalActionPlan.actions)
    $queue = @()
    foreach ($action in $actions) {
        $executionClass = Get-SiteAuditorV3RepairExecutionClass -Action $action -Contract $Contract
        $queue += [ordered]@{
            action_id = if ($action.ContainsKey("action_id")) { [string]$action.action_id } else { "unknown_action" }
            priority = if ($action.ContainsKey("priority")) { [string]$action.priority } else { "unknown" }
            count = if ($action.ContainsKey("count")) { [int]$action.count } else { 0 }
            action = if ($action.ContainsKey("action")) { [string]$action.action } else { $null }
            why = if ($action.ContainsKey("why")) { [string]$action.why } else { $null }
            target_module = if ($action.ContainsKey("target_module")) { [string]$action.target_module } else { $null }
            acceptance = if ($action.ContainsKey("acceptance")) { [string]$action.acceptance } else { $null }
            execution_class = $executionClass
            disposition = Get-SiteAuditorV3RepairExecutionDisposition -ExecutionClass $executionClass
            safe_to_auto_apply = $false
            execution_reason = switch ($executionClass) {
                "AGENT_REPAIR_CANDIDATE" { "Action targets an internal auditor capability owner, but v1 remains plan-only."; break }
                "TARGET_REPAIR_GUIDANCE" { "Action targets audited-site content/conversion and must remain guidance-only."; break }
                default { "Action owner is not mapped to a safe execution class; operator review required." }
            }
        }
    }

    $queue = @($queue | Sort-Object @{ Expression = { Get-SiteAuditorV3RepairPriorityRank -Priority $_.priority }; Ascending = $true }, @{ Expression = { -1 * [int]$_.count }; Ascending = $true }, @{ Expression = { [string]$_.action_id }; Ascending = $true })

    $summary = [ordered]@{
        total_actions = $queue.Count
        agent_repair_candidate_count = @($queue | Where-Object { $_.execution_class -eq "AGENT_REPAIR_CANDIDATE" }).Count
        target_repair_guidance_count = @($queue | Where-Object { $_.execution_class -eq "TARGET_REPAIR_GUIDANCE" }).Count
        operator_review_count = @($queue | Where-Object { $_.execution_class -eq "OPERATOR_REVIEW" }).Count
    }

    $top = if ($queue.Count -gt 0) { $queue[0] } else { $null }
    $oneNextExecutionAction = if ($top) {
        [ordered]@{
            action_id = [string]$top.action_id
            execution_class = [string]$top.execution_class
            disposition = [string]$top.disposition
            priority = [string]$top.priority
            target_module = [string]$top.target_module
            next_move = switch ([string]$top.execution_class) {
                "AGENT_REPAIR_CANDIDATE" { "Prepare a bounded internal repair/build task from this action."; break }
                "TARGET_REPAIR_GUIDANCE" { "Use this as audited-target guidance; do not mutate target automatically."; break }
                default { "Review and classify this action before any execution." }
            }
        }
    } else {
        [ordered]@{
            action_id = "none"
            execution_class = "NONE"
            disposition = "NO_ACTIONS"
            priority = "info"
            target_module = "operator"
            next_move = "No repair actions exist in FINAL_ACTION_PLAN.json. Preserve the finalized session as baseline truth."
        }
    }

    $status = if ($queue.Count -gt 0) { "PLAN_READY" } else { "NO_ACTIONS" }
    $createdAt = Get-SiteAuditorV3RepairUtcNow

    return [ordered]@{
        artifact = "REPAIR_EXECUTION_PLAN"
        schema_version = "1.0.0"
        status = $status
        created_at_utc = $createdAt
        session_id = if ($FinalActionPlan.ContainsKey("session_id")) { [string]$FinalActionPlan.session_id } else { $null }
        source_final_action_plan = "FINAL_ACTION_PLAN.json"
        source_run_report = $RunReportRelativePath
        source_verdict = if ($FinalActionPlan.ContainsKey("verdict")) { [string]$FinalActionPlan.verdict } else { "UNKNOWN" }
        plan_contract = [ordered]@{
            contract_id = [string]$Contract.contract_id
            schema_version = [string]$Contract.schema_version
            mutation_policy = [string]$Contract.classification_policy.mutation_policy
        }
        safety_gate = [ordered]@{
            status = "PASS"
            allow_target_mutation = [bool]$Contract.classification_policy.allow_target_mutation
            allow_repo_mutation = [bool]$Contract.classification_policy.allow_repo_mutation
            auto_apply_enabled = $false
            reason = [string]$Contract.safety_rule
        }
        queue_summary = $summary
        execution_queue = @($queue)
        one_next_execution_action = $oneNextExecutionAction
    }
}

function Convert-SiteAuditorV3RepairExecutionPlanToMarkdown {
    param([Parameter(Mandatory)]$Plan)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# REPAIR_EXECUTION_REPORT")
    $lines.Add("")
    $lines.Add("## Status")
    $lines.Add("- status: $($Plan.status)")
    $lines.Add("- session_id: $($Plan.session_id)")
    $lines.Add("- source_verdict: $($Plan.source_verdict)")
    $lines.Add("- created_at_utc: $($Plan.created_at_utc)")
    $lines.Add("")
    $lines.Add("## Safety gate")
    $lines.Add("- mutation_policy: $($Plan.plan_contract.mutation_policy)")
    $lines.Add("- allow_target_mutation: $($Plan.safety_gate.allow_target_mutation)")
    $lines.Add("- allow_repo_mutation: $($Plan.safety_gate.allow_repo_mutation)")
    $lines.Add("- reason: $($Plan.safety_gate.reason)")
    $lines.Add("")
    $lines.Add("## Queue summary")
    $lines.Add("- total_actions: $($Plan.queue_summary.total_actions)")
    $lines.Add("- agent_repair_candidate_count: $($Plan.queue_summary.agent_repair_candidate_count)")
    $lines.Add("- target_repair_guidance_count: $($Plan.queue_summary.target_repair_guidance_count)")
    $lines.Add("- operator_review_count: $($Plan.queue_summary.operator_review_count)")
    $lines.Add("")
    $lines.Add("## One next execution action")
    $lines.Add("- action_id: $($Plan.one_next_execution_action.action_id)")
    $lines.Add("- execution_class: $($Plan.one_next_execution_action.execution_class)")
    $lines.Add("- disposition: $($Plan.one_next_execution_action.disposition)")
    $lines.Add("- next_move: $($Plan.one_next_execution_action.next_move)")
    $lines.Add("")
    $lines.Add("## Execution queue")
    if (@($Plan.execution_queue).Count -eq 0) {
        $lines.Add("- No repair actions present.")
    } else {
        foreach ($item in @($Plan.execution_queue)) {
            $lines.Add("- [$($item.priority)] $($item.action_id) × $($item.count) -> $($item.execution_class) / $($item.disposition)")
        }
    }
    return ($lines -join [Environment]::NewLine)
}
