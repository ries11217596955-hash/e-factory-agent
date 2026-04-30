. (Join-Path $PSScriptRoot 'diagnostic_repair_guidance.ps1')
function New-SelfDiagnosticObject {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    $brokenCount = 0
    if ($null -ne $Report.problem_targets) {
        $brokenCount = @($Report.problem_targets | Where-Object { [string]$_.classification -eq 'broken' }).Count
    }

    [ordered]@{
        diagnostic_version = '1.0'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        output_dir = $OutputDir
        current_mode = if ($Report.mode) { [string]$Report.mode } else { 'LINK' }
        status = [string]$Report.status
        audit_confidence = [string]$Report.audit_confidence

        checked_layers = @(
            'route_discovery',
            'route_selection',
            'broken_route_detection',
            'visual_capture_attempt',
            'report_layer_consistency'
        )

        not_checked = @(
            'cta_interaction',
            'promise_to_destination',
            'benchmark_comparison',
            'content_quality_depth',
            'conversion_path_quality',
            'live_user_behavior'
        )

        known_findings = [ordered]@{
            broken_route_count = [int]$brokenCount
            decision_issue_type = if ($Report.decision_summary) { [string]$Report.decision_summary.issue_type } else { 'UNKNOWN' }
            system_problem_type = if ($Report.system_problem) { [string]$Report.system_problem.problem_type } else { 'UNKNOWN' }
        }

        limitations = @(
            'LINK mode is current execution lane, not full product capability.',
            'Screenshots are captured from selected visual targets, not yet prioritized by strongest defect.',
            'AGENT_MAP is runtime-written from static module map v1; it is not live code introspection yet.',
            'Human reports are low-value and need a separate report-value layer.'
        )

        current_bottleneck = 'human_report_low_value'
        next_safe_build_move = 'artifact_contract_cleanup_or_human_report_value_v1'
        repair_mode = (New-DiagnosticRepairGuidance -Report $Report)

        forbidden_next_steps = @(
            'do not add benchmark before report value is useful',
            'do not add CTA interaction before self-diagnostic and artifact contract are stable',
            'do not turn agent.ps1 into a giant file',
            'do not treat green CI as product readiness'
        )
    }
}

function Write-SelfDiagnosticJson {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [Parameter(Mandatory = $true)][string]$RootDir
    )

    $diag = New-SelfDiagnosticObject -Report $Report -OutputDir $OutputDir
    $json = $diag | ConvertTo-Json -Depth 20

    $outPath = Join-Path $OutputDir 'SELF_DIAGNOSTIC.json'
    $rootPath = Join-Path $RootDir 'SELF_DIAGNOSTIC.json'

    $json | Out-File -LiteralPath $outPath -Encoding UTF8
    $json | Out-File -LiteralPath $rootPath -Encoding UTF8

    Write-Host ("SELF_DIAGNOSTIC_JSON: WRITTEN " + $outPath)
}
