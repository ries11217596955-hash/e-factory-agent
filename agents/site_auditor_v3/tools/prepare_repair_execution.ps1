param(
    [Parameter(Mandatory)][string]$RunReportPath
)

$ErrorActionPreference = "Stop"

function Read-JsonHashtable {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 80
    )
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -Path $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $RunReportPath)) {
    throw "RUN_REPORT_NOT_FOUND_FOR_REPAIR_EXECUTION: $RunReportPath"
}

$reportPathResolved = (Resolve-Path -LiteralPath $RunReportPath).Path
$runRoot = Split-Path -Parent $reportPathResolved
$report = Read-JsonHashtable -Path $reportPathResolved
$finalization = if ($report.ContainsKey("finalization") -and $report.finalization) { $report.finalization } else { $null }

$existingRepairExecution = if ($report.ContainsKey("repair_execution") -and $report.repair_execution) { $report.repair_execution } else { $null }
if ($existingRepairExecution -and $existingRepairExecution.status -in @("PLAN_READY", "NO_ACTIONS")) {
    Write-Host "REPAIR_EXECUTION_STATUS=ALREADY_PREPARED"
    Write-Host "REPAIR_EXECUTION_PLAN=REPAIR_EXECUTION_PLAN.json"
    exit 0
}

if (-not $finalization -or [string]$finalization.status -ne "FINALIZED") {
    Write-Host "REPAIR_EXECUTION_STATUS=SKIPPED_NOT_FINALIZED"
    exit 0
}

$finalActionPlanPath = Join-Path $runRoot "FINAL_ACTION_PLAN.json"
if (-not (Test-Path -LiteralPath $finalActionPlanPath)) {
    throw "FINAL_ACTION_PLAN_NOT_FOUND_FOR_REPAIR_EXECUTION: $finalActionPlanPath"
}

$contractPath = "agents/site_auditor_v3/contracts/repair_execution_contract.json"
if (-not (Test-Path -LiteralPath $contractPath)) {
    throw "REPAIR_EXECUTION_CONTRACT_NOT_FOUND: $contractPath"
}

. (Resolve-Path "agents/site_auditor_v3/lib/repair_execution.ps1").Path

$contract = Read-JsonHashtable -Path $contractPath
$finalActionPlan = Read-JsonHashtable -Path $finalActionPlanPath

if ([string]$finalActionPlan.artifact -ne "FINAL_ACTION_PLAN") {
    throw "INVALID_FINAL_ACTION_PLAN_ARTIFACT: expected FINAL_ACTION_PLAN"
}

foreach ($field in @($contract.input_contract.required_final_action_plan_fields)) {
    if (-not $finalActionPlan.ContainsKey([string]$field)) {
        throw "FINAL_ACTION_PLAN_MISSING_FIELD: $field"
    }
}

$plan = New-SiteAuditorV3RepairExecutionPlan `
    -FinalActionPlan $finalActionPlan `
    -Contract $contract `
    -RunReportRelativePath "RUN_REPORT.json"

$planPath = Join-Path $runRoot "REPAIR_EXECUTION_PLAN.json"
$reportMdPath = Join-Path $runRoot "REPAIR_EXECUTION_REPORT.md"

Write-JsonFile -Value $plan -Path $planPath -Depth 100
Convert-SiteAuditorV3RepairExecutionPlanToMarkdown -Plan $plan | Set-Content -Path $reportMdPath -Encoding UTF8

$repairArtifacts = [ordered]@{
    repair_execution_plan = "REPAIR_EXECUTION_PLAN.json"
    repair_execution_report = "REPAIR_EXECUTION_REPORT.md"
}

$report.repair_execution = [ordered]@{
    status = [string]$plan.status
    prepared_at_utc = [string]$plan.created_at_utc
    artifacts = $repairArtifacts
    plan_contract = $plan.plan_contract
    safety_gate = $plan.safety_gate
    queue_summary = $plan.queue_summary
    one_next_execution_action = $plan.one_next_execution_action
}

Write-JsonFile -Value $report -Path $reportPathResolved -Depth 100

Write-Host "REPAIR_EXECUTION_STATUS=$($plan.status)"
Write-Host "REPAIR_EXECUTION_PLAN=$($repairArtifacts.repair_execution_plan)"
Write-Host "REPAIR_EXECUTION_REPORT=$($repairArtifacts.repair_execution_report)"
Write-Host "REPAIR_EXECUTION_ACTIONS=$($plan.queue_summary.total_actions)"
Write-Host "REPAIR_EXECUTION_NEXT_CLASS=$($plan.one_next_execution_action.execution_class)"
