$ErrorActionPreference = 'Stop'

$bundleRoot = Join-Path $PSScriptRoot 'audit_bundle'
$executionLogPath = Join-Path $bundleRoot 'EXECUTION_LOG.txt'
$reportPath = Join-Path $bundleRoot 'REPORT.txt'
$summaryPath = Join-Path $bundleRoot 'master_summary.json'
$bundleStatusPath = Join-Path $bundleRoot 'audit_bundle_summary.json'

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
            return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -ExitCode 0 -FailureMessage 'no zip input' -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $true)
        }
    }

    if ($modeUpper -eq 'URL' -and [string]::IsNullOrWhiteSpace($env:BASE_URL)) {
        Add-ExecutionLog 'Mode URL skipped: BASE_URL is missing.'
        return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -ExitCode 0 -FailureMessage 'missing BASE_URL' -CrashStage 'before_run_ps1' -OutboxCopied $false -ReportsCopied $false -Skipped $true)
    }

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

    $status = 'FAIL'
    if ($modeUpper -eq 'REPO' -and ($outboxCopied -or $reportsCopied)) {
        $status = 'PARTIAL'
    }

    Add-ExecutionLog "Mode $modeUpper finished with status=$status. crash_stage=$crashStage; reason=$failureMessage"
    return (New-ModeResult -Mode $modeUpper -Status $status -ExitCode $exitCode -FailureMessage $failureMessage -CrashStage $crashStage -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied -Skipped $false)
}

function Get-BundleStatusSummary {
    $statusIndex = @{}
    foreach ($result in $script:ModeResults) {
        $statusIndex[$result.mode] = $result
    }

    return [ordered]@{
        repo = if ($statusIndex.ContainsKey('REPO')) { $statusIndex['REPO'].status } else { 'FAIL' }
        zip = if ($statusIndex.ContainsKey('ZIP')) { $statusIndex['ZIP'].status } else { 'FAIL' }
        url = if ($statusIndex.ContainsKey('URL')) { $statusIndex['URL'].status } else { 'FAIL' }
    }
}

function Write-BundleDiagnostics {
    $hasFail = ($script:ModeResults | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
    $hasPartial = ($script:ModeResults | Where-Object { $_.status -eq 'PARTIAL' }).Count -gt 0
    $hasPass = ($script:ModeResults | Where-Object { $_.status -eq 'PASS' }).Count -gt 0

    $overallStatus = 'SKIPPED'
    if ($hasFail) { $overallStatus = 'FAIL' }
    elseif ($hasPartial) { $overallStatus = 'PARTIAL' }
    elseif ($hasPass) { $overallStatus = 'PASS' }

    $bundleSummary = Get-BundleStatusSummary
    $bundleSummary | ConvertTo-Json -Depth 4 | Out-File -FilePath $bundleStatusPath -Encoding utf8

    $summary = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        overall_status = $overallStatus
        mode_results = @($script:ModeResults)
        bundle_status = $bundleSummary
    }

    $summary | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add('SITE_AUDITOR TRI-AUDIT BUNDLE REPORT')
    $reportLines.Add("GENERATED AT: $($summary.generated_at)")
    $reportLines.Add("OVERALL STATUS: $overallStatus")
    $reportLines.Add('')
    $reportLines.Add('MODE RESULTS:')

    foreach ($result in $script:ModeResults) {
        $reportLines.Add("- $($result.mode): $($result.status)")
        if ($result.skipped) {
            $reportLines.Add("  skipped_reason: $($result.failure_message)")
            $reportLines.Add("  crash_stage: $($result.crash_stage)")
        }
        elseif ($result.status -eq 'FAIL' -or $result.status -eq 'PARTIAL') {
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
    $reportLines.Add('BUNDLE STATUS: audit_bundle/audit_bundle_summary.json')

    $reportLines | Out-File -FilePath $reportPath -Encoding utf8
    $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
}

function Get-StatusLine {
    param([hashtable]$Result)

    if ([string]::IsNullOrWhiteSpace($Result.failure_message)) {
        return "$($Result.mode): $($Result.status)"
    }

    return "$($Result.mode): $($Result.status) (reason: $($Result.failure_message))"
}

function Write-TriAuditSummary {
    $repoResult = $script:ModeResults | Where-Object { $_.mode -eq 'REPO' } | Select-Object -First 1
    $zipResult = $script:ModeResults | Where-Object { $_.mode -eq 'ZIP' } | Select-Object -First 1
    $urlResult = $script:ModeResults | Where-Object { $_.mode -eq 'URL' } | Select-Object -First 1

    Write-Host '=== TRI-AUDIT SUMMARY ==='
    if ($null -ne $repoResult) { Write-Host (Get-StatusLine -Result $repoResult) }
    if ($null -ne $zipResult) { Write-Host (Get-StatusLine -Result $zipResult) }
    if ($null -ne $urlResult) { Write-Host (Get-StatusLine -Result $urlResult) }
}

function Get-BundleExitCode {
    $allFailed = ($script:ModeResults.Count -gt 0) -and (($script:ModeResults | Where-Object { $_.status -eq 'FAIL' }).Count -eq $script:ModeResults.Count)
    if ($allFailed) {
        return 1
    }

    return 0
}

try {
    Ensure-Directory -Path $bundleRoot
    Add-ExecutionLog 'Bundle execution started.'

    # REPO isolated subrun
    try {
        Add-ExecutionLog 'REPO subrun attempt started.'
        $script:ModeResults.Add((Invoke-ModeSafely -Mode 'REPO'))
    }
    catch {
        $failureMessage = $_.Exception.Message
        Add-ExecutionLog "REPO subrun crashed: $failureMessage"
        $script:ModeResults.Add((New-ModeResult -Mode 'REPO' -Status 'FAIL' -ExitCode 1 -FailureMessage $failureMessage -CrashStage 'subrun_wrapper' -OutboxCopied $false -ReportsCopied $false -Skipped $false))
    }

    # ZIP isolated subrun
    try {
        Add-ExecutionLog 'ZIP subrun attempt started.'
        $script:ModeResults.Add((Invoke-ModeSafely -Mode 'ZIP'))
    }
    catch {
        $failureMessage = $_.Exception.Message
        Add-ExecutionLog "ZIP subrun crashed: $failureMessage"
        $script:ModeResults.Add((New-ModeResult -Mode 'ZIP' -Status 'FAIL' -ExitCode 1 -FailureMessage $failureMessage -CrashStage 'subrun_wrapper' -OutboxCopied $false -ReportsCopied $false -Skipped $false))
    }

    # URL isolated subrun
    try {
        Add-ExecutionLog 'URL subrun attempt started.'
        $script:ModeResults.Add((Invoke-ModeSafely -Mode 'URL'))
    }
    catch {
        $failureMessage = $_.Exception.Message
        Add-ExecutionLog "URL subrun crashed: $failureMessage"
        $script:ModeResults.Add((New-ModeResult -Mode 'URL' -Status 'FAIL' -ExitCode 1 -FailureMessage $failureMessage -CrashStage 'subrun_wrapper' -OutboxCopied $false -ReportsCopied $false -Skipped $false))
    }
}
catch {
    $topFailureMessage = $_.Exception.Message
    Add-ExecutionLog "Top-level bundle crash: $topFailureMessage"
}
finally {
    try {
        Write-BundleDiagnostics
        Add-ExecutionLog 'Bundle diagnostics written successfully.'
    }
    catch {
        $fallback = "[$((Get-Date).ToString('o'))] Failed to write diagnostics cleanly: $($_.Exception.Message)"
        $script:ExecutionLog.Add($fallback)
        $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
    }
}

Write-TriAuditSummary
$exitCode = Get-BundleExitCode
Write-Host "Bundle completed with exit code $exitCode."
exit $exitCode
