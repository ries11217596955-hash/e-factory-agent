$ErrorActionPreference = 'Stop'

$bundleRoot = Join-Path $PSScriptRoot 'audit_bundle'
$executionLogPath = Join-Path $bundleRoot 'EXECUTION_LOG.txt'
$reportPath = Join-Path $bundleRoot 'REPORT.txt'
$summaryPath = Join-Path $bundleRoot 'master_summary.json'
$bundleStatusPath = Join-Path $bundleRoot 'audit_bundle_summary.json'

$script:ExecutionLog = New-Object System.Collections.Generic.List[string]
$script:ModeResults = New-Object System.Collections.Generic.List[object]
$script:ActiveModes = @('REPO')

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
        [string]$Reason,
        [int]$ExitCode,
        [bool]$Executed,
        [bool]$OutboxCopied,
        [bool]$ReportsCopied
    )

    $artifactsPresent = $OutboxCopied -or $ReportsCopied

    return [ordered]@{
        mode = $Mode
        status = $Status
        reason = $Reason
        artifacts_present = $artifactsPresent
        exit_code = $ExitCode
        executed = $Executed
        outbox_copied = $OutboxCopied
        reports_copied = $ReportsCopied
        timestamp = (Get-Date).ToString('o')
    }
}

function Get-ModeResult {
    param([string]$Mode)

    return $script:ModeResults | Where-Object { $_.mode -eq $Mode } | Select-Object -First 1
}

function Convert-ToSummaryEntry {
    param($Result)

    if ($null -eq $Result) {
        return [ordered]@{
            status = 'FAIL'
            reason = 'subrun missing'
            artifacts_present = $false
        }
    }

    return [ordered]@{
        status = $Result.status
        reason = if ([string]::IsNullOrWhiteSpace($Result.reason)) { '' } else { $Result.reason }
        artifacts_present = [bool]$Result.artifacts_present
    }
}

function Invoke-ModeSafely {
    param([string]$Mode)

    $modeUpper = $Mode.ToUpperInvariant()
    $modeOutputRoot = Join-Path $bundleRoot $modeUpper.ToLowerInvariant()
    Ensure-Directory -Path $modeOutputRoot

    if ($script:ActiveModes -notcontains $modeUpper) {
        $stageReason = 'SKIPPED_BY_STAGE_ACTIVATION'
        Add-ExecutionLog "Mode $modeUpper forced skipped: $stageReason"
        return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -Reason $stageReason -ExitCode 0 -Executed $false -OutboxCopied $false -ReportsCopied $false)
    }

    if ($modeUpper -eq 'ZIP') {
        $zipInbox = Join-Path $PSScriptRoot 'input/inbox'
        $zipExists = Test-Path $zipInbox -PathType Container -and ((Get-ChildItem -Path $zipInbox -Filter '*.zip' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
        if (-not $zipExists) {
            Add-ExecutionLog "Mode ZIP skipped: no ZIP payload found in $zipInbox"
            return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -Reason 'no zip input' -ExitCode 0 -Executed $false -OutboxCopied $false -ReportsCopied $false)
        }
    }

    if ($modeUpper -eq 'URL' -and [string]::IsNullOrWhiteSpace($env:BASE_URL)) {
        Add-ExecutionLog 'Mode URL skipped: BASE_URL is missing.'
        return (New-ModeResult -Mode $modeUpper -Status 'SKIPPED' -Reason 'missing BASE_URL' -ExitCode 0 -Executed $false -OutboxCopied $false -ReportsCopied $false)
    }

    Add-ExecutionLog "Mode $modeUpper starting run.ps1 invocation."

    $exitCode = 1
    $failureMessage = ''

    try {
        & (Join-Path $PSScriptRoot 'run.ps1') -MODE $modeUpper
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    }
    catch {
        $failureMessage = $_.Exception.Message
        Add-ExecutionLog "Mode $modeUpper invocation crashed: $failureMessage"
        $exitCode = 1
    }

    $outboxCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'outbox') -Destination (Join-Path $modeOutputRoot 'outbox')
    $reportsCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'reports') -Destination (Join-Path $modeOutputRoot 'reports')

    if ($exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($failureMessage)) {
        Add-ExecutionLog "Mode $modeUpper completed successfully."
        return (New-ModeResult -Mode $modeUpper -Status 'PASS' -Reason '' -ExitCode $exitCode -Executed $true -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied)
    }

    if ([string]::IsNullOrWhiteSpace($failureMessage)) {
        $failureMessage = "run.ps1 exited with code $exitCode"
    }

    $status = 'FAIL'
    if ($modeUpper -eq 'REPO' -and ($outboxCopied -or $reportsCopied)) {
        $status = 'PARTIAL'
    }

    Add-ExecutionLog "Mode $modeUpper finished with status=$status; reason=$failureMessage"
    return (New-ModeResult -Mode $modeUpper -Status $status -Reason $failureMessage -ExitCode $exitCode -Executed $true -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied)
}

function Ensure-PrimaryRepoResult {
    $repoResult = Get-ModeResult -Mode 'REPO'
    if ($null -eq $repoResult) {
        Add-ExecutionLog 'REPO result missing; injecting deterministic FAIL result.'
        $script:ModeResults.Add((New-ModeResult -Mode 'REPO' -Status 'FAIL' -Reason 'REPO subrun was not executed' -ExitCode 1 -Executed $false -OutboxCopied $false -ReportsCopied $false))
    }
}

function Get-OverallStatus {
    $repoResult = Get-ModeResult -Mode 'REPO'
    if ($null -eq $repoResult -or -not $repoResult.executed) {
        return 'FAIL'
    }

    if ($repoResult.status -eq 'FAIL') {
        return 'FAIL'
    }

    $hasWarnings = ($script:ModeResults | Where-Object { $_.mode -ne 'REPO' -and $_.status -in @('FAIL', 'PARTIAL', 'SKIPPED') }).Count -gt 0
    if ($repoResult.status -eq 'PARTIAL' -or $hasWarnings) {
        return 'PASS_WITH_WARNINGS'
    }

    return 'PASS'
}

function Build-BundleStatusSummary {
    $repoResult = Get-ModeResult -Mode 'REPO'
    $zipResult = Get-ModeResult -Mode 'ZIP'
    $urlResult = Get-ModeResult -Mode 'URL'

    return [ordered]@{
        repo = Convert-ToSummaryEntry -Result $repoResult
        zip = Convert-ToSummaryEntry -Result $zipResult
        url = Convert-ToSummaryEntry -Result $urlResult
        overall = Get-OverallStatus
    }
}

function Write-BundleDiagnostics {
    Ensure-Directory -Path $bundleRoot

    $bundleSummary = Build-BundleStatusSummary
    $bundleSummary | ConvertTo-Json -Depth 6 | Out-File -FilePath $bundleStatusPath -Encoding utf8

    $summary = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        overall_status = $bundleSummary.overall
        mode_results = @($script:ModeResults)
        bundle_status = $bundleSummary
    }
    $summary | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add('SITE_AUDITOR TRI-AUDIT BUNDLE REPORT')
    $reportLines.Add("GENERATED AT: $($summary.generated_at)")
    $reportLines.Add("OVERALL STATUS: $($bundleSummary.overall)")
    $reportLines.Add('')
    $reportLines.Add('MODE RESULTS:')

    foreach ($result in $script:ModeResults) {
        $reportLines.Add("- $($result.mode): $($result.status)")
        if (-not [string]::IsNullOrWhiteSpace($result.reason)) {
            $reportLines.Add("  reason: $($result.reason)")
        }
        $reportLines.Add("  executed: $($result.executed)")
        $reportLines.Add("  exit_code: $($result.exit_code)")
        $reportLines.Add("  artifacts_present: $($result.artifacts_present)")
        $reportLines.Add("  artifacts: outbox=$($result.outbox_copied); reports=$($result.reports_copied)")
    }

    $reportLines.Add('')
    $reportLines.Add('EXECUTION LOG: audit_bundle/EXECUTION_LOG.txt')
    $reportLines.Add('MASTER SUMMARY: audit_bundle/master_summary.json')
    $reportLines.Add('BUNDLE STATUS: audit_bundle/audit_bundle_summary.json')

    $reportLines | Out-File -FilePath $reportPath -Encoding utf8
    $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
}

function Write-TriAuditSummary {
    $bundleSummary = Build-BundleStatusSummary

    Write-Host '=== TRI-AUDIT RESULT ==='
    Write-Host "REPO: $($bundleSummary.repo.status)$(if (-not [string]::IsNullOrWhiteSpace($bundleSummary.repo.reason)) { " ($($bundleSummary.repo.reason))" })"
    Write-Host "ZIP: $($bundleSummary.zip.status)$(if (-not [string]::IsNullOrWhiteSpace($bundleSummary.zip.reason)) { " ($($bundleSummary.zip.reason))" })"
    Write-Host "URL: $($bundleSummary.url.status)$(if (-not [string]::IsNullOrWhiteSpace($bundleSummary.url.reason)) { " ($($bundleSummary.url.reason))" })"
    Write-Host "OVERALL: $($bundleSummary.overall)"
}

function Get-BundleExitCode {
    $repoResult = Get-ModeResult -Mode 'REPO'
    if ($null -eq $repoResult -or -not $repoResult.executed) {
        return 1
    }

    return 0
}

function Validate-BundleScriptSyntax {
    Add-ExecutionLog 'Validating PowerShell syntax...'

    $parseErrors = @()
    $tokens = @()
    $source = Get-Content -Raw -Path $PSCommandPath
    [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $errorSummary = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        Add-ExecutionLog "PowerShell parser reported syntax issues: $errorSummary"
    }
    else {
        Add-ExecutionLog 'PowerShell parser validation passed.'
    }

    $invalidLogicalTokens = $tokens | Where-Object {
        $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Identifier -and $_.Text -match '^(?i:and|or)$'
    }

    if ($invalidLogicalTokens.Count -gt 0) {
        $tokenSummary = ($invalidLogicalTokens | ForEach-Object { "'$($_.Text)' at line $($_.Extent.StartLineNumber)" }) -join ', '
        Add-ExecutionLog "Invalid logical token(s) detected; correction needed: $tokenSummary"
    }
    else {
        Add-ExecutionLog 'No invalid logical operator tokens detected.'
    }
}

try {
    Ensure-Directory -Path $bundleRoot
    Validate-BundleScriptSyntax
    Add-ExecutionLog 'Bundle execution started.'

    foreach ($mode in @('REPO', 'ZIP', 'URL')) {
        try {
            Add-ExecutionLog "$mode subrun attempt started."
            $script:ModeResults.Add((Invoke-ModeSafely -Mode $mode))
        }
        catch {
            $failureMessage = $_.Exception.Message
            Add-ExecutionLog "$mode subrun crashed before deterministic result capture: $failureMessage"
            $script:ModeResults.Add((New-ModeResult -Mode $mode -Status 'FAIL' -Reason $failureMessage -ExitCode 1 -Executed $false -OutboxCopied $false -ReportsCopied $false))
        }
    }

    Ensure-PrimaryRepoResult
}
catch {
    $topFailureMessage = $_.Exception.Message
    Add-ExecutionLog "Top-level bundle crash: $topFailureMessage"
    Ensure-PrimaryRepoResult
}
finally {
    try {
        Write-BundleDiagnostics
        Add-ExecutionLog 'Bundle diagnostics written successfully.'
    }
    catch {
        Ensure-Directory -Path $bundleRoot
        $fallback = "[$((Get-Date).ToString('o'))] Failed to write diagnostics cleanly: $($_.Exception.Message)"
        $script:ExecutionLog.Add($fallback)

        if (-not (Test-Path $reportPath)) {
            @(
                'SITE_AUDITOR TRI-AUDIT BUNDLE REPORT',
                'OVERALL STATUS: FAIL',
                'reason: diagnostics writer crashed',
                "details: $($_.Exception.Message)",
                'BUNDLE STATUS: unavailable'
            ) | Out-File -FilePath $reportPath -Encoding utf8
        }

        if (-not (Test-Path $bundleStatusPath)) {
            [ordered]@{
                repo = [ordered]@{ status = 'FAIL'; reason = 'diagnostics writer crashed'; artifacts_present = $false }
                zip = [ordered]@{ status = 'FAIL'; reason = 'diagnostics writer crashed'; artifacts_present = $false }
                url = [ordered]@{ status = 'FAIL'; reason = 'diagnostics writer crashed'; artifacts_present = $false }
                overall = 'FAIL'
            } | ConvertTo-Json -Depth 6 | Out-File -FilePath $bundleStatusPath -Encoding utf8
        }

        if (-not (Test-Path $summaryPath)) {
            [ordered]@{
                generated_at = (Get-Date).ToString('o')
                overall_status = 'FAIL'
                mode_results = @($script:ModeResults)
                bundle_status = (Get-Content -Raw -Path $bundleStatusPath | ConvertFrom-Json)
            } | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8
        }

        $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
    }
}

Write-TriAuditSummary
$exitCode = Get-BundleExitCode
Write-Host "Bundle completed with exit code $exitCode."
exit $exitCode
