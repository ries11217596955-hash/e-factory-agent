$ErrorActionPreference = 'Stop'

$bundleRoot = Join-Path $PSScriptRoot 'audit_bundle'
$executionLogPath = Join-Path $bundleRoot 'EXECUTION_LOG.txt'
$reportPath = Join-Path $bundleRoot 'REPORT.txt'
$summaryPath = Join-Path $bundleRoot 'master_summary.json'
$bundleStatusPath = Join-Path $bundleRoot 'audit_bundle_summary.json'

$script:ExecutionLog = New-Object System.Collections.Generic.List[string]

function Add-ExecutionLog {
    param([string]$Message)

    $timestamp = (Get-Date).ToString('o')
    $line = "[$timestamp] $Message"
    $script:ExecutionLog.Add($line)
    Write-Host $line
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -Path $Source -PathType Container)) {
        return $false
    }

    Ensure-Directory -Path $Destination
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force -ErrorAction SilentlyContinue
    return $true
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

    [ordered]@{
        mode = $Mode
        status = $Status
        reason = $Reason
        exit_code = $ExitCode
        executed = $Executed
        outbox_copied = $OutboxCopied
        reports_copied = $ReportsCopied
        artifacts_present = ($OutboxCopied -or $ReportsCopied)
        timestamp = (Get-Date).ToString('o')
    }
}

function Invoke-RepoExecution {
    $mode = 'REPO'
    $modeRoot = Join-Path $bundleRoot 'repo'
    Ensure-Directory -Path $modeRoot

    Add-ExecutionLog 'REPO subrun started.'

    $exitCode = 1
    $reason = ''

    try {
        & (Join-Path $PSScriptRoot 'run.ps1') -MODE $mode
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    }
    catch {
        $reason = $_.Exception.Message
        $exitCode = 1
        Add-ExecutionLog "REPO subrun crashed: $reason"
    }

    $outboxCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'outbox') -Destination (Join-Path $modeRoot 'outbox')
    $reportsCopied = Copy-IfExists -Source (Join-Path $PSScriptRoot 'reports') -Destination (Join-Path $modeRoot 'reports')

    $status = 'FAIL'
    if ($exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($reason)) {
        $status = 'OK'
        Add-ExecutionLog 'REPO subrun completed with OK.'
    }
    elseif ($outboxCopied -or $reportsCopied) {
        $status = 'PARTIAL'
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = "run.ps1 exited with code $exitCode"
        }
        Add-ExecutionLog "REPO subrun completed with PARTIAL: $reason"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = "run.ps1 exited with code $exitCode"
        }
        Add-ExecutionLog "REPO subrun completed with FAIL: $reason"
    }

    return (New-ModeResult -Mode $mode -Status $status -Reason $reason -ExitCode $exitCode -Executed $true -OutboxCopied $outboxCopied -ReportsCopied $reportsCopied)
}

function New-ForcedSkippedModeResult {
    param([string]$Mode)

    Add-ExecutionLog "$Mode forced skipped by staged activation."
    return (New-ModeResult -Mode $Mode -Status 'SKIPPED' -Reason 'SKIPPED_BY_STAGE_ACTIVATION' -ExitCode 0 -Executed $false -OutboxCopied $false -ReportsCopied $false)
}

function Invoke-ExecutionStage {
    Add-ExecutionLog 'STAGE 1 (EXECUTION) started.'

    $results = New-Object System.Collections.Generic.List[object]
    $results.Add((Invoke-RepoExecution))
    $results.Add((New-ForcedSkippedModeResult -Mode 'ZIP'))
    $results.Add((New-ForcedSkippedModeResult -Mode 'URL'))

    Add-ExecutionLog 'STAGE 1 (EXECUTION) completed.'
    return @($results)
}

function Get-BundleLogicalStatus {
    param([object[]]$ModeResults)

    $logicalResults = @($ModeResults | Where-Object { $_.status -in @('OK', 'PARTIAL', 'FAIL') })

    if ($logicalResults | Where-Object { $_.status -eq 'FAIL' }) {
        return 'FAIL'
    }

    if ($logicalResults | Where-Object { $_.status -eq 'PARTIAL' }) {
        return 'PARTIAL'
    }

    return 'OK'
}

function Invoke-AssemblyStage {
    param([object[]]$ModeResults)

    Add-ExecutionLog 'STAGE 2 (ASSEMBLY) started.'

    try {
        $safeModeResults = if ($null -eq $ModeResults) { @() } else { @($ModeResults) }

        $repoResult = $safeModeResults | Where-Object { $_.mode -eq 'REPO' } | Select-Object -First 1
        $zipResult = $safeModeResults | Where-Object { $_.mode -eq 'ZIP' } | Select-Object -First 1
        $urlResult = $safeModeResults | Where-Object { $_.mode -eq 'URL' } | Select-Object -First 1

        $repo = if ($null -ne $repoResult) {
            @{
                name = 'repo'
                status = [string]$repoResult.status
                reason = [string]$repoResult.reason
                artifacts_present = [bool]$repoResult.artifacts_present
            }
        }
        else {
            $null
        }

        $zip = if ($null -ne $zipResult) {
            @{
                name = 'zip'
                status = [string]$zipResult.status
                reason = [string]$zipResult.reason
                artifacts_present = [bool]$zipResult.artifacts_present
            }
        }
        else {
            $null
        }

        $url = if ($null -ne $urlResult) {
            @{
                name = 'url'
                status = [string]$urlResult.status
                reason = [string]$urlResult.reason
                artifacts_present = [bool]$urlResult.artifacts_present
            }
        }
        else {
            $null
        }

        $repo = [hashtable]$repo
        $zip = [hashtable]$zip
        $url = [hashtable]$url

        $repo = $repo ?? @{
            name = 'repo'
            status = 'FAIL'
            reason = 'NULL_RESULT'
            artifacts_present = $false
        }
        $zip = $zip ?? @{
            name = 'zip'
            status = 'FAIL'
            reason = 'NULL_RESULT'
            artifacts_present = $false
        }
        $url = $url ?? @{
            name = 'url'
            status = 'FAIL'
            reason = 'NULL_RESULT'
            artifacts_present = $false
        }

        $bundle = @{
            repo = $repo
            zip = $zip
            url = $url
        }

        $statuses = @($repo.status, $zip.status, $url.status)

        if ($statuses -contains 'FAIL') {
            $overall = 'FAIL'
        }
        elseif ($statuses -contains 'PARTIAL') {
            $overall = 'PARTIAL'
        }
        else {
            $overall = 'OK'
        }

        $bundleStatus = [ordered]@{
            repo = [ordered]@{
                status = [string]$bundle.repo.status
                reason = [string]$bundle.repo.reason
                artifacts_present = [bool]$bundle.repo.artifacts_present
            }
            zip = [ordered]@{
                status = [string]$bundle.zip.status
                reason = [string]$bundle.zip.reason
                artifacts_present = [bool]$bundle.zip.artifacts_present
            }
            url = [ordered]@{
                status = [string]$bundle.url.status
                reason = [string]$bundle.url.reason
                artifacts_present = [bool]$bundle.url.artifacts_present
            }
            overall = $overall
        }

        $assembled = [ordered]@{
            generated_at = (Get-Date).ToString('o')
            mode_results = $safeModeResults
            bundle_status = $bundleStatus
            overall_status = $overall
        }

        Add-ExecutionLog 'ASSEMBLY_OK'
        Add-ExecutionLog "STAGE 2 (ASSEMBLY) completed with overall=$overall."
        return $assembled
    }
    catch {
        $errorMessage = $_.Exception.Message
        $bundle = @{
            overall = 'FAIL'
            reason = $errorMessage
        }

        $assembled = [ordered]@{
            generated_at = (Get-Date).ToString('o')
            mode_results = if ($null -eq $ModeResults) { @() } else { @($ModeResults) }
            bundle_status = $bundle
            overall_status = 'FAIL'
        }

        Add-ExecutionLog "ASSEMBLY_FAIL: $errorMessage"
        return $assembled
    }
}

function New-ReportLines {
    param($Assembled)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SITE_AUDITOR TRI-AUDIT BUNDLE REPORT')
    $lines.Add("GENERATED AT: $($Assembled.generated_at)")
    $lines.Add("OVERALL STATUS: $($Assembled.overall_status)")
    $lines.Add('')
    $lines.Add('MODE RESULTS:')

    foreach ($result in $Assembled.mode_results) {
        $lines.Add("- $($result.mode): $($result.status)")
        if (-not [string]::IsNullOrWhiteSpace($result.reason)) {
            $lines.Add("  reason: $($result.reason)")
        }
        $lines.Add("  executed: $($result.executed)")
        $lines.Add("  exit_code: $($result.exit_code)")
        $lines.Add("  artifacts_present: $($result.artifacts_present)")
    }

    $lines.Add('')
    $lines.Add('EXECUTION LOG: audit_bundle/EXECUTION_LOG.txt')
    $lines.Add('MASTER SUMMARY: audit_bundle/master_summary.json')
    $lines.Add('BUNDLE STATUS: audit_bundle/audit_bundle_summary.json')

    return $lines
}

function Invoke-WritingStage {
    param($Assembled)

    Add-ExecutionLog 'STAGE 3 (WRITING) started.'

    Ensure-Directory -Path $bundleRoot

    try {
        $assembled.bundle_status | ConvertTo-Json -Depth 6 | Out-File -FilePath $bundleStatusPath -Encoding utf8
        $assembled | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8
        (New-ReportLines -Assembled $Assembled) | Out-File -FilePath $reportPath -Encoding utf8
        $script:ExecutionLog | Out-File -FilePath $executionLogPath -Encoding utf8
    }
    catch {
        Add-ExecutionLog "STAGE 3 (WRITING) encountered an error: $($_.Exception.Message)"
    }

    Add-ExecutionLog 'STAGE 3 (WRITING) completed.'
}

function New-FallbackAssembled {
    param(
        [object[]]$ModeResults,
        [string]$FailureMessage
    )

    $safeModeResults = if ($null -eq $ModeResults) { @() } else { @($ModeResults) }

    if (-not ($safeModeResults | Where-Object { $_.mode -eq 'REPO' })) {
        $safeModeResults = @(
            (New-ModeResult -Mode 'REPO' -Status 'FAIL' -Reason 'REPO subrun was not captured due to runtime crash' -ExitCode 1 -Executed $false -OutboxCopied $false -ReportsCopied $false)
        ) + $safeModeResults
    }

    return [ordered]@{
        generated_at = (Get-Date).ToString('o')
        mode_results = $safeModeResults
        bundle_status = [ordered]@{
            repo = [ordered]@{
                status = 'FAIL'
                reason = $FailureMessage
                artifacts_present = $false
            }
            zip = [ordered]@{
                status = 'SKIPPED'
                reason = 'SKIPPED_BY_STAGE_ACTIVATION'
                artifacts_present = $false
            }
            url = [ordered]@{
                status = 'SKIPPED'
                reason = 'SKIPPED_BY_STAGE_ACTIVATION'
                artifacts_present = $false
            }
            overall = 'FAIL'
        }
        overall_status = 'FAIL'
    }
}

function Get-BundleExitCode {
    param(
        $Assembled,
        [bool]$HadRuntimeCrash
    )

    if ($HadRuntimeCrash -or $null -eq $Assembled) {
        return 1
    }

    return 0
}

$assembled = $null
$modeResults = @()
$hadRuntimeCrash = $false

try {
    Ensure-Directory -Path $bundleRoot
    Add-ExecutionLog 'Bundle execution started.'

    $modeResults = Invoke-ExecutionStage
    $assembled = Invoke-AssemblyStage -ModeResults $modeResults
}
catch {
    $hadRuntimeCrash = $true
    $fatalMessage = $_.Exception.Message
    Add-ExecutionLog "Bundle runtime failure: $fatalMessage"
    $assembled = New-FallbackAssembled -ModeResults $modeResults -FailureMessage $fatalMessage
}

Invoke-WritingStage -Assembled $assembled

$exitCode = Get-BundleExitCode -Assembled $assembled -HadRuntimeCrash $hadRuntimeCrash
Write-Host "Bundle completed with overall status $($assembled.overall_status) and exit code $exitCode."
exit $exitCode
