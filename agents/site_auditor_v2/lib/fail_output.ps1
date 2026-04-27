function Write-MinimalFailRunReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootDir,
        [Parameter(Mandatory = $true)]
        [string]$FailPhase,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        [Parameter(Mandatory = $true)]
        [string]$LastCompletedStage
    )

    $runReportPath = Join-Path $RootDir 'RUN_REPORT.json'

    try {
        $screenshotsPath = Join-Path $RootDir 'screenshots'
        $screenshotCount = 0
        if (Test-Path -LiteralPath $screenshotsPath -PathType Container) {
            $screenshotCount = [int]@(Get-ChildItem -LiteralPath $screenshotsPath -File -Recurse).Count
        }

        $visualManifestPath = Join-Path $RootDir 'visual_manifest.json'
        $failureSummaryPath = Join-Path $RootDir 'failure_summary.json'
        $actionReportPath = Join-Path $RootDir 'ACTION_REPORT.txt'
        $routesSummaryPath = Join-Path $RootDir 'ROUTES_SUMMARY.json'
        $auditSummaryPath = Join-Path $RootDir 'AUDIT_SUMMARY.json'

        $minimalReport = [ordered]@{
            status = 'FAIL'
            fail_phase = [string]$FailPhase
            error_message = [string]$ErrorMessage
            last_completed_stage = [string]$LastCompletedStage
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            evidence = [ordered]@{
                screenshot_count = [int]$screenshotCount
                has_visual_manifest = [bool](Test-Path -LiteralPath $visualManifestPath -PathType Leaf)
                has_failure_summary = [bool](Test-Path -LiteralPath $failureSummaryPath -PathType Leaf)
                has_action_report = [bool](Test-Path -LiteralPath $actionReportPath -PathType Leaf)
                has_routes_summary = [bool](Test-Path -LiteralPath $routesSummaryPath -PathType Leaf)
                has_audit_summary = [bool](Test-Path -LiteralPath $auditSummaryPath -PathType Leaf)
            }
        }

        $json = $minimalReport | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($runReportPath, $json)

        return [PSCustomObject]@{
            status = 'ok'
            run_report_path = [string]$runReportPath
            error_message = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            status = 'error'
            run_report_path = [string]$runReportPath
            error_message = [string]$_.Exception.Message
        }
    }
}
