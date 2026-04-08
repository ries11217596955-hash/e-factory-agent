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
        [string]$RepoRoot,
        [bool]$TargetRepoBound,
        [bool]$ArtifactsPresent,
        [string]$OutboxPath,
        [string]$ReportsPath
    )

    [ordered]@{
        mode = $Mode
        executed = $Executed
        status = $Status
        reason = $Reason
        exit_code = $ExitCode
        repo_root = $RepoRoot
        target_repo_bound = $TargetRepoBound
        artifacts_present = $ArtifactsPresent
        outbox_path = $OutboxPath
        reports_path = $ReportsPath
    }
}

function Test-ModeResultShape {
    param(
        [hashtable]$Result,
        [string]$Mode
    )

    if ($null -eq $Result) {
        return $false
    }

    $requiredKeys = @(
        'mode',
        'executed',
        'status',
        'reason',
        'exit_code',
        'repo_root',
        'target_repo_bound',
        'artifacts_present',
        'outbox_path',
        'reports_path'
    )

    foreach ($key in $requiredKeys) {
        if (-not $Result.Contains($key)) {
            Add-ExecutionLog "ASSEMBLY_INPUT_FAIL mode=$Mode missing_key=$key"
            return $false
        }
    }

    return $true
}

function Invoke-RepoExecution {
    $mode = 'REPO'
    $modeRoot = Join-Path $bundleRoot 'repo'
    Ensure-Directory -Path $modeRoot

    Add-ExecutionLog 'REPO subrun started.'

    $repoRoot = if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH)) { $null } else { $env:TARGET_REPO_PATH }
    $targetRepoBound = $false
    $exitCode = 1
    $reason = ''
    $outboxPath = $null
    $reportsPath = $null

    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        $reason = 'TARGET_REPO_PATH is empty'
        Add-ExecutionLog "REPO_BINDING_FAIL reason=$reason"
        $result = New-ModeResult -Mode $mode -Status 'FAIL' -Reason $reason -ExitCode 1 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null
        Add-ExecutionLog 'REPO_RESULT_NORMALIZED'
        return $result
    }

    if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) {
        $reason = "TARGET_REPO_PATH does not exist: $repoRoot"
        Add-ExecutionLog "REPO_BINDING_FAIL reason=$reason"
        $result = New-ModeResult -Mode $mode -Status 'FAIL' -Reason $reason -ExitCode 1 -Executed $false -RepoRoot $repoRoot -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null
        Add-ExecutionLog 'REPO_RESULT_NORMALIZED'
        return $result
    }

    $targetRepoBound = $true
    Add-ExecutionLog "REPO_BINDING_OK path=$repoRoot"

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
    if ($outboxCopied) { $outboxPath = Join-Path $modeRoot 'outbox' }
    if ($reportsCopied) { $reportsPath = Join-Path $modeRoot 'reports' }

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

    $result = New-ModeResult -Mode $mode -Status $status -Reason $reason -ExitCode $exitCode -Executed $true -RepoRoot $repoRoot -TargetRepoBound $targetRepoBound -ArtifactsPresent ($outboxCopied -or $reportsCopied) -OutboxPath $outboxPath -ReportsPath $reportsPath
    Add-ExecutionLog 'REPO_RESULT_NORMALIZED'
    return $result
}

function New-ForcedSkippedModeResult {
    param([string]$Mode)

    Add-ExecutionLog "$Mode forced skipped by staged activation."
    return (New-ModeResult -Mode $Mode -Status 'SKIPPED' -Reason 'SKIPPED_BY_STAGE_ACTIVATION' -ExitCode 0 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null)
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

function Get-RepoScreenshotManifest {
    $repoRoot = Join-Path $bundleRoot 'repo'
    $sourceRoots = @(
        Join-Path $repoRoot 'reports'
        Join-Path $repoRoot 'outbox'
    )

    $manifest = New-Object System.Collections.Generic.List[object]
    $nameCounts = @{}

    foreach ($sourceRoot in $sourceRoots) {
        if (-not (Test-Path -Path $sourceRoot -PathType Container)) {
            continue
        }

        $pngFiles = Get-ChildItem -Path $sourceRoot -Filter '*.png' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name, FullName
        foreach ($pngFile in $pngFiles) {
            $baseName = $pngFile.Name
            if (-not $nameCounts.ContainsKey($baseName)) {
                $nameCounts[$baseName] = 0
            }

            $nameCounts[$baseName] += 1
            $copyName = if ($nameCounts[$baseName] -eq 1) {
                $baseName
            }
            else {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
                $ext = [System.IO.Path]::GetExtension($baseName)
                "$stem-$($nameCounts[$baseName])$ext"
            }

            $manifest.Add([ordered]@{
                source = $pngFile.FullName
                relative_path = "bundle_artifacts/$copyName"
                file_name = $copyName
            })
        }
    }

    return @($manifest)
}

function Invoke-AssemblyStage {
    param([object[]]$ModeResults)

    Add-ExecutionLog 'STAGE 2 (ASSEMBLY) started.'

    $safeResults = New-Object System.Collections.Generic.List[hashtable]
    foreach ($modeResult in @($ModeResults)) {
        if ($modeResult -is [hashtable] -and (Test-ModeResultShape -Result $modeResult -Mode ([string]$modeResult.mode))) {
            $safeResults.Add($modeResult)
        }
        else {
            $rawMode = if ($null -ne $modeResult -and $modeResult.PSObject.Properties['mode']) { [string]$modeResult.mode } else { 'UNKNOWN' }
            Add-ExecutionLog "ASSEMBLY_INPUT_MALFORMED mode=$rawMode"
            $safeResults.Add((New-ModeResult -Mode $rawMode -Status 'FAIL' -Reason 'MALFORMED_SUBRUN_RESULT' -ExitCode 1 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null))
        }
    }

    Add-ExecutionLog 'ASSEMBLY_INPUT_OK'
    $repoResult = @($safeResults) | Where-Object { $_.mode -eq 'REPO' } | Select-Object -First 1
    if ($null -eq $repoResult) {
        $repoResult = New-ModeResult -Mode 'REPO' -Status 'FAIL' -Reason 'REPO subrun was not captured' -ExitCode 1 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null
        $safeResults.Insert(0, $repoResult)
        Add-ExecutionLog 'REPO result was missing; injected deterministic FAIL result.'
    }

    $bundleLogicalStatus = Get-BundleLogicalStatus -ModeResults @($safeResults)

    $repoScreenshotManifest = Get-RepoScreenshotManifest
    $repoArtifacts = @($repoScreenshotManifest | ForEach-Object { $_.relative_path })

    $bundleStatus = [ordered]@{
        repo = [ordered]@{
            status = $repoResult.status
            reason = $repoResult.reason
            artifacts_present = [bool]$repoResult.artifacts_present
            artifacts = $repoArtifacts
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
        overall = $bundleLogicalStatus
    }

    $assembled = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        mode_results = @($safeResults)
        bundle_status = $bundleStatus
        overall_status = $bundleLogicalStatus
    }

    Add-ExecutionLog "STAGE 2 (ASSEMBLY) completed with overall=$bundleLogicalStatus."
    return $assembled
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
    $lines.Add('')
    $lines.Add('SCREENSHOTS')
    $lines.Add('-----------')

    $repoArtifacts = @()
    if ($null -ne $Assembled.bundle_status -and $null -ne $Assembled.bundle_status.repo -and $null -ne $Assembled.bundle_status.repo.artifacts) {
        $repoArtifacts = @($Assembled.bundle_status.repo.artifacts)
    }

    if ($repoArtifacts.Count -eq 0) {
        $lines.Add('No screenshots captured')
    }
    else {
        foreach ($artifact in $repoArtifacts) {
            $lines.Add("- $([System.IO.Path]::GetFileName([string]$artifact))")
        }
    }

    return $lines
}

function Invoke-WritingStage {
    param($Assembled)

    Add-ExecutionLog 'STAGE 3 (WRITING) started.'

    Ensure-Directory -Path $bundleRoot
    $bundleArtifactsRoot = Join-Path $bundleRoot 'bundle_artifacts'
    Ensure-Directory -Path $bundleArtifactsRoot

    $repoScreenshotManifest = Get-RepoScreenshotManifest
    foreach ($artifact in $repoScreenshotManifest) {
        $destinationPath = Join-Path $bundleRoot $artifact.relative_path
        $destinationDirectory = Split-Path -Path $destinationPath -Parent
        Ensure-Directory -Path $destinationDirectory
        Copy-Item -Path $artifact.source -Destination $destinationPath -Force -ErrorAction SilentlyContinue
    }

    if ($null -eq $Assembled.bundle_status.repo) {
        $Assembled.bundle_status.repo = [ordered]@{}
    }
    $Assembled.bundle_status.repo.artifacts = @($repoScreenshotManifest | ForEach-Object { $_.relative_path })

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
            (New-ModeResult -Mode 'REPO' -Status 'FAIL' -Reason 'REPO subrun was not captured due to runtime crash' -ExitCode 1 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null)
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

function Normalize-Result {
    param(
        $r,
        [string]$name
    )

    if ($null -eq $r -or $r -isnot [hashtable]) {
        return @{
            status = 'FAIL'
            reason = "${name}_INVALID_RESULT"
        }
    }

    return @{
        status = [string]$r.status
        reason = [string]$r.reason
    }
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
$global:LASTEXITCODE = $exitCode

$overall = if ($null -ne $assembled -and $null -ne $assembled.bundle_status -and $null -ne $assembled.bundle_status.overall) {
    $assembled.bundle_status.overall
}
else {
    $assembled.overall_status
}

$repo = if ($null -ne $assembled -and $null -ne $assembled.bundle_status) { $assembled.bundle_status.repo } else { $null }
$zip = if ($null -ne $assembled -and $null -ne $assembled.bundle_status) { $assembled.bundle_status.zip } else { $null }
$url = if ($null -ne $assembled -and $null -ne $assembled.bundle_status) { $assembled.bundle_status.url } else { $null }

$repo = Normalize-Result $repo 'repo'
$zip = Normalize-Result $zip 'zip'
$url = Normalize-Result $url 'url'

$manifest = @{
    overall = [string]$overall
    repo = $repo
    zip = $zip
    url = $url
}

$manifest = $manifest | ConvertTo-Json -Depth 5 | ConvertFrom-Json
Add-ExecutionLog 'MANIFEST_NORMALIZED_OK'
return $manifest
