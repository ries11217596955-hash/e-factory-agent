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
        [int]$Depth = 60
    )
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -Path $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $RunReportPath)) {
    throw "RUN_REPORT_NOT_FOUND: $RunReportPath"
}

. (Resolve-Path "agents/site_auditor_v3/lib/session_finalization.ps1").Path

$reportPathResolved = (Resolve-Path -LiteralPath $RunReportPath).Path
$runRoot = Split-Path -Parent $reportPathResolved
$report = Read-JsonHashtable -Path $reportPathResolved
$auditSession = if ($report.ContainsKey("audit_session") -and $report.audit_session) { $report.audit_session } else { @{} }
$sessionSummary = if ($report.ContainsKey("session_summary") -and $report.session_summary) { $report.session_summary } else { @{} }

$sessionId = if ($auditSession.ContainsKey("session_id")) { [string]$auditSession.session_id } else { "" }
$totalPending = if ($auditSession.ContainsKey("total_pending_count")) { [int]$auditSession.total_pending_count } else { -1 }
$nextAction = if ($auditSession.ContainsKey("next_action")) { [string]$auditSession.next_action } else { "UNKNOWN" }

if ([string]::IsNullOrWhiteSpace($sessionId)) {
    Write-Host "FINALIZATION_STATUS=SKIPPED_NO_SESSION"
    exit 0
}

if ($totalPending -gt 0) {
    Write-Host "FINALIZATION_STATUS=SKIPPED_PENDING"
    Write-Host "FINALIZATION_PENDING_COUNT=$totalPending"
    exit 0
}

if ($nextAction -notin @("FINAL_SUMMARY", "REVIEW_FINAL_OPERATOR_REPORT")) {
    Write-Host "FINALIZATION_STATUS=SKIPPED_NEXT_ACTION"
    Write-Host "FINALIZATION_NEXT_ACTION=$nextAction"
    exit 0
}

$ledgerPath = Join-Path "agents/site_auditor_v3/runs/sessions" $sessionId
$ledgerPath = Join-Path $ledgerPath "AUDIT_SESSION_LEDGER.json"
if (-not (Test-Path -LiteralPath $ledgerPath)) {
    throw "LEDGER_NOT_FOUND_FOR_FINALIZATION: $ledgerPath"
}

$ledger = Read-JsonHashtable -Path $ledgerPath
$runId = if ($report.ContainsKey("run_id")) { [string]$report.run_id } else { "unknown" }
$finalization = New-SiteAuditorV3SessionFinalization -Ledger $ledger -RunId $runId -RunRoot $runRoot

Write-JsonFile -Value $finalization.session_aggregate -Path $finalization.artifact_paths.session_aggregate -Depth 80
$finalization.final_operator_report | Set-Content -Path $finalization.artifact_paths.final_operator_report -Encoding UTF8
Write-JsonFile -Value $finalization.final_action_plan -Path $finalization.artifact_paths.final_action_plan -Depth 80
Write-JsonFile -Value $finalization.findings_index -Path $finalization.artifact_paths.final_findings_index -Depth 80

$finalArtifactsRelative = [ordered]@{
    session_aggregate = "SESSION_AGGREGATE.json"
    final_operator_report = "FINAL_OPERATOR_REPORT.md"
    final_action_plan = "FINAL_ACTION_PLAN.json"
    final_findings_index = "FINAL_FINDINGS_INDEX.json"
}

$ledger.finalization_status = "FINALIZED"
$ledger.finalized_at_utc = [string]$finalization.finalized_at_utc
$ledger.final_artifacts = $finalArtifactsRelative
$ledger.final_decision = $finalization.session_aggregate.final_decision
$ledger.next_action = "REVIEW_FINAL_OPERATOR_REPORT"
Write-JsonFile -Value $ledger -Path $ledgerPath -Depth 80

$auditSession.finalization_status = "FINALIZED"
$auditSession.finalized_at_utc = [string]$finalization.finalized_at_utc
$auditSession.final_artifacts = $finalArtifactsRelative
$auditSession.final_verdict = [string]$finalization.session_aggregate.final_decision.verdict
$auditSession.aggregation_completeness = $finalization.session_aggregate.aggregation_completeness
$auditSession.next_action = "REVIEW_FINAL_OPERATOR_REPORT"
$report.audit_session = $auditSession

if (-not $report.ContainsKey("session_summary") -or -not $report.session_summary) {
    $report.session_summary = [ordered]@{}
}
$report.session_summary.session_status = "FINALIZED"
$report.session_summary.next_action = "REVIEW_FINAL_OPERATOR_REPORT"
$report.session_summary.finalization_status = "FINALIZED"
$report.session_summary.final_artifacts = $finalArtifactsRelative
$report.session_summary.final_verdict = [string]$finalization.session_aggregate.final_decision.verdict
$report.session_summary.aggregation_completeness = $finalization.session_aggregate.aggregation_completeness

$report.finalization = [ordered]@{
    status = "FINALIZED"
    finalized_at_utc = [string]$finalization.finalized_at_utc
    artifacts = $finalArtifactsRelative
    final_verdict = [string]$finalization.session_aggregate.final_decision.verdict
    one_next_action = $finalization.session_aggregate.final_decision.one_next_action
    aggregation_completeness = $finalization.session_aggregate.aggregation_completeness
}

Write-JsonFile -Value $report -Path $reportPathResolved -Depth 80

Write-Host "FINALIZATION_STATUS=FINALIZED"
Write-Host "FINALIZATION_SESSION_ID=$sessionId"
Write-Host "FINALIZATION_VERDICT=$($finalization.session_aggregate.final_decision.verdict)"
Write-Host "FINALIZATION_REPORT=$($finalArtifactsRelative.final_operator_report)"
