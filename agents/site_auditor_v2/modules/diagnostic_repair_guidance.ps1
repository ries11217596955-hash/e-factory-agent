function New-DiagnosticRepairGuidance {
    param(
        [Parameter(Mandatory = $true)][object]$Report
    )

    $failPhase = if ($Report.PSObject.Properties['fail_phase'] -and $Report.fail_phase) {
        [string]$Report.fail_phase
    } else {
        'NONE'
    }

    $ownerModule = switch -Regex ($failPhase) {
        'LINK|FETCH|ROUTE' { 'agents/site_auditor_v2/modules/stage_link_fetch.ps1'; break }
        'RECON' { 'agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1'; break }
        'REPORT' { 'agents/site_auditor_v2/modules/report_layer.ps1'; break }
        'OUTPUT' { 'agents/site_auditor_v2/lib/post_output.ps1'; break }
        default { 'NONE_FOR_SUCCESSFUL_RUN'; break }
    }

    $nextStep = if ($failPhase -eq 'NONE') {
        'No runtime repair needed. Use SELF_DIAGNOSTIC.current_bottleneck for next build move.'
    } else {
        'Inspect RUN_REPORT.json and failure_summary.json, then patch only the suspected owner module.'
    }

    [ordered]@{
        purpose = 'Help operator repair the agent from the latest run artifact.'
        fail_phase = $failPhase
        suspected_owner_module = $ownerModule
        open_this_file = $ownerModule
        next_debug_step = $nextStep
        forbidden_debug_steps = @(
            'do not refactor agent.ps1 blindly',
            'do not patch report_layer unless fail_phase or stack trace points there',
            'do not open benchmark or CTA capability while repairing runtime failure',
            'do not use Codex before root cause and owner file are known'
        )
    }
}
