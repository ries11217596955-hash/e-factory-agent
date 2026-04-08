$ErrorActionPreference = 'Stop'

$bundleRoot = Join-Path $PSScriptRoot 'audit_bundle'
$executionLogPath = Join-Path $bundleRoot 'EXECUTION_LOG.txt'
$reportPath = Join-Path $bundleRoot 'REPORT.txt'
$summaryPath = Join-Path $bundleRoot 'master_summary.json'

$script:ExecutionLog = New-Object System.Collections.Generic.List[string]
$script:ModeResults = New-Object System.Collections.Generic.List[object]

function Add-ExecutionLog {
    param([string]$Message)

    $timestamp = (Get-Date).ToString('o')
    $line = "[$timestamp] $Message"
    $script:ExecutionLog.Add($line)
    Write-Host $line
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Reset-ModeArtifacts {
    $outboxPath = Join-Path $PSScriptRoot 'outbox'
    $reportsPath = Join-Path $PSScriptRoot 'reports'

    if (Test-Path $outboxPath) {
        Remove-Item -Path $outboxPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $reportsPath) {
        Remove-Item -Path $reportsPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path $Source) {
        Ensure-Directory -Path $Destination
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }

    return $false
}

function New-ModeResult {
    param(
        [string]$Mode,
        [string]$Status,
        [int]$ExitCode,
        [string]$FailureMessage,
        [string]$CrashStage,
        [bool]$OutboxCopied,
        [bool]$ReportsCopied,
        [bool]$Skipped
    )

    return [ordered]@{
        mode = $Mode
        status = $Status
        exit_code = $ExitCode
        skipped = $Skipped
        failure_message = $FailureMessage
        crash_stage = $CrashStage
        outbox_copied = $OutboxCopied
        reports_copied = $ReportsCopied
        timestamp = (Get-Date).ToString('o')
    }
}

function Invoke-ModeSafely {
    param([string]$Mode)

    $modeUpper = $Mode.ToUpperInvariant()
    $modeOutputRoot = Join-Path $bundleRoot $modeUpper.ToLowerInvariant()
    Ensure-Directory -Path $modeOutputRoot

    if ($modeUpper -eq 'ZIP') {
        $zipInbox = Join-Path $PSScriptRoot 'input/inbox'
        $zipExists = Test-Path $zipInbox -PathType Container -and ((Get-ChildItem -Path $zipInbox -Filter '*.zip' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
        if (-not $zipExists) {
            Add-ExecutionLog "Mode ZIP skipped: no ZIP payload found in $zipInbox"
            return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -ExitCode 0 -FailureMessage 'Missing ZIP payload in input/inbox.' -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $true)
        }
    }

    if ($modeUpper -eq 'URL' -and [string]::IsNullOrWhiteSpace($env:BASE_URL)) {
        Add-ExecutionLog 'Mode URL skipped: BASE_URL is missing.'
        return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -ExitCode 0 -FailureMessage 'Missing BASE_URL.' -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $true)
    }

    Reset-ModeArtifacts
    Add-ExecutionLog "Mode $modeUpper starting run.ps1 invocation."

    $exitCode = 1
    $crashStage = $null
    $failureMessage = $null

    try {
        & (Join-Path $PSScriptRoot 'run.ps1') -MODE $modeUpper
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    }
    catch {
        $crashStage = 'after_run_ps1_invocation'
        $failureMessage = $_.Exception.Message
        Add-ExecutionLog "Mode $modeUpper invocation crashed: $failureMessage"
        $exitCode = 1
    }

    $outboxCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'outbox') -Destination (Join-Path $modeOutputRoot 'outbox')
    $reportsCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'reports') -Destination (Join-Path $modeOutputRoot 'reports')

    if ($exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($failureMessage)) {
        Add-ExecutionLog "Mode $modeUpper completed successfully."
        return (New-ModeResult -Mode $modeUpper -Status 'PASS' -ExitCode $exitCode -FailureMessage $null -CrashStage $null -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied -Skipped $false)
    }

    if ([string]::IsNullOrWhiteSpace($crashStage)) {
        $crashStage = 'after_run_ps1_invocation'
    }
    if ([string]::IsNullOrWhiteSpace($failureMessage)) {
        $failureMessage = "run.ps1 exited with code $exitCode"
    }

    $status = if ($outboxCopied -or $reportsCopied) { 'PARTIAL' } else { 'FAIL' }
    Add-ExecutionLog "Mode $modeUpper completed with status $status. crash_stage=$crashStage; reason=$failureMessage"
    return (New-ModeResult -Mode $modeUpper -Status $status -ExitCode $exitCode -FailureMessage $failureMessage -CrashStage $crashStage -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied -Skipped $false)
}

function Write-BundleDiagnostics {
    $hasFail = ($script:ModeResults | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
    $hasPartial = ($script:ModeResults | Where-Object { $_.status -eq 'PARTIAL' }).Count -gt 0
    $hasPass = ($script:ModeResults | Where-Object { $_.status -eq 'PASS' }).Count -gt 0

    $overallStatus = 'SKIPPED'
    if ($hasFail) { $overallStatus = 'FAIL' }
    elseif ($hasPartial) { $overallStatus = 'PARTIAL' }
    elseif ($hasPass) { $overallStatus = 'PASS' }

    $summary = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        calibration_mode = $true
        overall_status = $overallStatus
        mode_results = @($script:ModeResults)
        notes = @(
            'Calibration mode preserves artifacts for operator review.',
            'Bundle exits with code 0 after diagnostics are written.',
            (if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_DIAG)) { 'Target repo checkout diagnostics: not provided by workflow.' } else { "Target repo checkout diagnostics: $($env:TARGET_REPO_DIAG)" })
        )
    }

    $summary | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add('SITE_AUDITOR TRI-AUDIT BUNDLE REPORT')
    $reportLines.Add("GENERATED AT: $($summary.generated_at)")
    $reportLines.Add("OVERALL STATUS: $overallStatus")
    $reportLines.Add('CALIBRATION MODE: enabled (bundle exits 0 after diagnostics)')
    $reportLines.Add('')
    $reportLines.Add('MODE RESULTS:')

    foreach ($result in $script:ModeResults) {
        $reportLines.Add("- $($result.mode): $($result.status)")
        if ($result.skipped) {
            $reportLines.Add("  skipped_reason: $($result.failure_message)")
            $reportLines.Add("  crash_stage: $($result.crash_stage)")
        }
        elseif ($result.status -eq 'FAIL') {
            $reportLines.Add("  failure_message: $($result.failure_message)")
            $reportLines.Add("  crash_stage: $($result.crash_stage)")
            $reportLines.Add("  exit_code: $($result.exit_code)")
        }
        else {
            $reportLines.Add("  exit_code: $($result.exit_code)")
        }
        $reportLines.Add("  artifacts: outbox=$($result.outbox_copied); reports=$($result.reports_copied)")
    }

    $reportLines.Add('')
    $reportLines.Add('EXECUTION LOG: audit_bundle/EXECUTION_LOG.txt')
    $reportLines.Add('MASTER SUMMARY: audit_bundle/master_summary.json')

    $reportLines | Out-File -FilePath $reportPath -Encoding utf8
    $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
}

try {
    Ensure-Directory -Path $bundleRoot
    Add-ExecutionLog 'Bundle execution started.'

    foreach ($mode in @('REPO', 'ZIP', 'URL')) {
        try {
            $result = Invoke-ModeSafely -Mode $mode
            $script:ModeResults.Add($result)
        }
        catch {
            $failureMessage = $_.Exception.Message
            Add-ExecutionLog "Mode $mode wrapper crash: $failureMessage"
            $script:ModeResults.Add((New-ModeResult -Mode $mode -Status 'FAIL' -ExitCode 1 -FailureMessage $failureMessage -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $false))
        }
    }
}
catch {
    $topFailureMessage = $_.Exception.Message
    Add-ExecutionLog "Top-level bundle crash: $topFailureMessage"
    if (($script:ModeResults | Measure-Object).Count -eq 0) {
        $script:ModeResults.Add((New-ModeResult -Mode 'BUNDLE' -Status 'FAIL' -ExitCode 1 -FailureMessage $topFailureMessage -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $false))
    }
}
finally {
    try {
        Write-BundleDiagnostics
        Add-ExecutionLog 'Bundle diagnostics written successfully.'
        $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
    }
    catch {
        $fallback = "[$((Get-Date).ToString('o'))] Failed to write diagnostics cleanly: $($_.Exception.Message)"
        $script:ExecutionLog.Add($fallback)
        $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
    }
}

Write-Host 'Bundle calibration mode: exiting with code 0 after diagnostics.'
exit 0
