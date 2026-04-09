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

    Add-ExecutionLog 'MODE_RESULTS_COUNT=$($results.Count)'
    Add-ExecutionLog 'STAGE 1 (EXECUTION) completed.'
    return $results
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

    Add-ExecutionLog "SCREENSHOT_MANIFEST_COUNT=$($manifest.Count)"
    return $manifest
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
    $repoEvidence = Get-RepoEvidence
    if ($null -eq $repoResult) {
        if ($repoEvidence.has_outbox -or $repoEvidence.has_reports) {
            $repoOutboxPath = if ($repoEvidence.has_outbox) { $repoEvidence.outbox_dir } else { $null }
            $repoReportsPath = if ($repoEvidence.has_reports) { $repoEvidence.reports_dir } else { $null }
            $repoResult = New-ModeResult -Mode 'REPO' -Status 'PARTIAL' -Reason 'REPO mode result object missing, but REPO artifacts/reports were captured' -ExitCode 1 -Executed $true -RepoRoot $repoEvidence.repo_root -TargetRepoBound $false -ArtifactsPresent $true -OutboxPath $repoOutboxPath -ReportsPath $repoReportsPath
            Add-ExecutionLog 'REPO result missing but artifacts exist; synthesized PARTIAL result from evidence.'
        }
        else {
            $repoResult = New-ModeResult -Mode 'REPO' -Status 'FAIL' -Reason 'REPO subrun was not captured' -ExitCode 1 -Executed $false -RepoRoot $null -TargetRepoBound $false -ArtifactsPresent $false -OutboxPath $null -ReportsPath $null
            Add-ExecutionLog 'REPO result was missing and no repo artifacts were found; injected deterministic FAIL result.'
        }
        $safeResults.Insert(0, $repoResult)
    }
    elseif ($repoResult.status -eq 'FAIL' -and $repoResult.reason -in @('MALFORMED_SUBRUN_RESULT', 'REPO subrun was not captured') -and ($repoEvidence.has_outbox -or $repoEvidence.has_reports)) {
        $repoResult.status = 'PARTIAL'
        $repoResult.reason = "REPO result was $($repoResult.reason), but repo evidence exists and was preserved"
        $repoResult.executed = $true
        $repoResult.artifacts_present = $true
        if ([string]::IsNullOrWhiteSpace([string]$repoResult.outbox_path) -and $repoEvidence.has_outbox) { $repoResult.outbox_path = $repoEvidence.outbox_dir }
        if ([string]::IsNullOrWhiteSpace([string]$repoResult.reports_path) -and $repoEvidence.has_reports) { $repoResult.reports_path = $repoEvidence.reports_dir }
        Add-ExecutionLog 'REPO malformed/missing result was reconciled to PARTIAL because artifacts/reports exist.'
    }

    $bundleLogicalStatus = Get-BundleLogicalStatus -ModeResults @($safeResults)

    $repoScreenshotManifest = Get-RepoScreenshotManifest
    $repoArtifacts = @()
    foreach ($item in $repoScreenshotManifest) {
        $repoArtifacts += [string]$item.relative_path
    }

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

function Get-FileLinesIfPresent {
    param([string]$Path)

    if (Test-Path -Path $Path -PathType Leaf) {
        return @(Get-Content -Path $Path -ErrorAction SilentlyContinue)
    }

    return @()
}

function Get-JsonIfPresent {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json)
    }
    catch {
        Add-ExecutionLog "JSON_READ_FAIL path=$Path reason=$($_.Exception.Message)"
        return $null
    }
}

function Get-RepoEvidence {
    $repoRoot = Join-Path $bundleRoot 'repo'
    $reportsDir = Join-Path $repoRoot 'reports'
    $outboxDir = Join-Path $repoRoot 'outbox'

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    $runManifestPath = Join-Path $reportsDir 'run_manifest.json'
    $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
    $repoReportPath = Join-Path $outboxDir 'REPORT.txt'

    return [ordered]@{
        repo_root = $repoRoot
        reports_dir = $reportsDir
        outbox_dir = $outboxDir
        has_outbox = (Test-Path -Path $outboxDir -PathType Container)
        has_reports = (Test-Path -Path $reportsDir -PathType Container)
        has_audit_result = (Test-Path -Path $auditResultPath -PathType Leaf)
        has_run_manifest = (Test-Path -Path $runManifestPath -PathType Leaf)
        has_visual_manifest = (Test-Path -Path $visualManifestPath -PathType Leaf)
        has_repo_report = (Test-Path -Path $repoReportPath -PathType Leaf)
        audit_result_path = $auditResultPath
        run_manifest_path = $runManifestPath
        visual_manifest_path = $visualManifestPath
        repo_report_path = $repoReportPath
    }
}

function Get-ListItemsFromLines {
    param([string[]]$Lines)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($lineRaw in @($Lines)) {
        $line = [string]$lineRaw
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $clean = $line.Trim()
        if ($clean -match '^\-\s+(.+)$') {
            $clean = $matches[1].Trim()
        }
        elseif ($clean -match '^\d+\)\s+(.+)$') {
            $clean = $matches[1].Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($clean) -and $clean -ne 'none') {
            $items.Add($clean)
        }
    }

    return @($items)
}

function Get-SectionItems {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string[]]$StopSections
    )

    $capture = $false
    $captured = New-Object System.Collections.Generic.List[string]
    foreach ($lineRaw in @($Lines)) {
        $line = ([string]$lineRaw).Trim()
        if (-not $capture) {
            if ($line -ieq $Section) {
                $capture = $true
            }
            continue
        }

        if ($StopSections -icontains $line) {
            break
        }

        if ($line -match '^\-\s+(.+)$') {
            $captured.Add($matches[1].Trim())
        }
    }

    return @($captured)
}

function Add-UniqueLimitedItems {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [hashtable]$Seen,
        [string[]]$Candidates,
        [int]$MaxItems = 5
    )

    foreach ($candidateRaw in @($Candidates)) {
        if ($Target.Count -ge $MaxItems) {
            break
        }

        $candidate = [string]$candidateRaw
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $key = $candidate.Trim().ToLowerInvariant()
        if (-not $Seen.ContainsKey($key)) {
            $Seen[$key] = $true
            $Target.Add($candidate.Trim())
        }
    }
}

function New-OperatorReportData {
    param($Assembled)

    $repoRoot = Join-Path $bundleRoot 'repo'
    $reportsDir = Join-Path $repoRoot 'reports'
    $outboxDir = Join-Path $repoRoot 'outbox'

    $reportLines = Get-FileLinesIfPresent -Path (Join-Path $outboxDir 'REPORT.txt')
    $priorityLines = Get-ListItemsFromLines -Lines (Get-FileLinesIfPresent -Path (Join-Path $reportsDir '00_PRIORITY_ACTIONS.txt'))
    $topIssueLines = Get-ListItemsFromLines -Lines (Get-FileLinesIfPresent -Path (Join-Path $reportsDir '01_TOP_ISSUES.txt'))
    $auditResult = Get-JsonIfPresent -Path (Join-Path $reportsDir 'audit_result.json')

    $p0 = New-Object System.Collections.Generic.List[string]
    $p1 = New-Object System.Collections.Generic.List[string]
    $p2 = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    Add-UniqueLimitedItems -Target $p0 -Seen $seen -Candidates (Get-SectionItems -Lines $reportLines -Section 'P0:' -StopSections @('P1:', 'P2:', 'DO NEXT:'))
    Add-UniqueLimitedItems -Target $p1 -Seen $seen -Candidates (Get-SectionItems -Lines $reportLines -Section 'P1:' -StopSections @('P2:', 'DO NEXT:'))
    Add-UniqueLimitedItems -Target $p2 -Seen $seen -Candidates (Get-SectionItems -Lines $reportLines -Section 'P2:' -StopSections @('DO NEXT:'))

    if ($p0.Count -eq 0 -and $p1.Count -eq 0 -and $p2.Count -eq 0 -and $topIssueLines.Count -gt 0) {
        if ($Assembled.overall_status -eq 'FAIL') {
            Add-UniqueLimitedItems -Target $p0 -Seen $seen -Candidates $topIssueLines
        }
        elseif ($Assembled.overall_status -eq 'PARTIAL') {
            Add-UniqueLimitedItems -Target $p1 -Seen $seen -Candidates $topIssueLines
        }
        else {
            Add-UniqueLimitedItems -Target $p2 -Seen $seen -Candidates $topIssueLines
        }
    }

    if ($null -ne $auditResult) {
        $liveLayer = if ($null -ne $auditResult.PSObject.Properties['live']) { $auditResult.live } else { $null }
        $liveSummary = if ($null -ne $liveLayer -and $null -ne $liveLayer.PSObject.Properties['summary']) { $liveLayer.summary } else { $null }
        if ($null -ne $liveSummary) {
            $pageQualityStatus = [string](if ($null -ne $liveSummary.PSObject.Properties['page_quality_status']) { $liveSummary.page_quality_status } else { '' })
            $failureStage = [string](if ($null -ne $liveSummary.PSObject.Properties['failure_stage']) { $liveSummary.failure_stage } else { 'unknown' })
            $evaluationError = [string](if ($null -ne $liveSummary.PSObject.Properties['evaluation_error']) { $liveSummary.evaluation_error } else { '' })
            $totalRoutes = [int](if ($null -ne $liveSummary.PSObject.Properties['total_routes']) { $liveSummary.total_routes } else { 0 })
            $rawRoutes = [int](if ($null -ne $liveSummary.PSObject.Properties['raw_route_entries']) { $liveSummary.raw_route_entries } else { 0 })
            $normalizedRoutes = [int](if ($null -ne $liveSummary.PSObject.Properties['normalized_route_entries']) { $liveSummary.normalized_route_entries } else { 0 })

            if ($pageQualityStatus -eq 'NOT_EVALUATED') {
                $detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "${failureStage}: $evaluationError" } else { $failureStage }
                if ($totalRoutes -gt 0 -or $rawRoutes -gt 0 -or $normalizedRoutes -gt 0) {
                    Add-UniqueLimitedItems -Target $p1 -Seen $seen -Candidates @("Page quality rollup is NOT_EVALUATED but route evidence exists ($detail).")
                }
                else {
                    Add-UniqueLimitedItems -Target $p2 -Seen $seen -Candidates @("Page quality rollup is NOT_EVALUATED ($detail).")
                }
            }
            elseif ($pageQualityStatus -eq 'PARTIAL') {
                Add-UniqueLimitedItems -Target $p1 -Seen $seen -Candidates @('Page quality rollup is PARTIAL; review dropped/unsupported route entries.')
            }
        }
    }

    $doNext = New-Object System.Collections.Generic.List[string]
    $doNextFromReport = Get-SectionItems -Lines $reportLines -Section 'DO NEXT:' -StopSections @()
    Add-UniqueLimitedItems -Target $doNext -Seen @{} -Candidates $doNextFromReport -MaxItems 3
    if ($doNext.Count -eq 0) {
        Add-UniqueLimitedItems -Target $doNext -Seen @{} -Candidates $priorityLines -MaxItems 3
    }

    if ($doNext.Count -eq 0) {
        if ($p0.Count -gt 0) {
            $doNext.Add('Fix P0 items and rerun SITE_AUDITOR in REPO mode.')
            $doNext.Add('Validate TARGET_REPO_PATH and confirm reports are regenerated.')
        }
        elseif ($Assembled.overall_status -eq 'PARTIAL') {
            $doNext.Add('Resolve the blocking warnings causing PARTIAL status.')
            $doNext.Add('Rerun SITE_AUDITOR to complete missing coverage.')
        }
        else {
            $doNext.Add('Track remaining findings in remediation backlog.')
            $doNext.Add('Rerun SITE_AUDITOR after major site changes.')
        }
    }

    $coreProblem = 'No critical problem was found in the collected audit evidence.'
    if ($p0.Count -gt 0) {
        $coreProblem = $p0[0]
    }
    elseif ($Assembled.overall_status -eq 'FAIL') {
        $repoReason = [string]$Assembled.bundle_status.repo.reason
        if ([string]::IsNullOrWhiteSpace($repoReason)) {
            $repoReason = 'audit execution failed before useful evidence was produced'
        }
        $coreProblem = "Critical audit failure: $repoReason."
    }
    elseif ($p1.Count -gt 0) {
        $coreProblem = $p1[0]
    }
    elseif ($Assembled.overall_status -eq 'PARTIAL') {
        $coreProblem = 'Partial run produced actionable findings, but full coverage is incomplete.'
    }

    return @{
        core_problem = $coreProblem
        p0 = @($p0)
        p1 = @($p1)
        p2 = @($p2)
        do_next = @($doNext | Select-Object -First 3)
        reports_dir = $reportsDir
        outbox_dir = $outboxDir
    }
}

function Write-OperatorBundleFiles {
    param(
        $Assembled,
        [hashtable]$OperatorData
    )

    $confidence = if ($Assembled.overall_status -eq 'PARTIAL') {
        'Confidence: Limited - PARTIAL run; findings reflect available evidence only.'
    }
    elseif ($Assembled.overall_status -eq 'FAIL') {
        'Confidence: Limited - execution failed or incomplete; review execution log and retained evidence.'
    }
    else {
        'Confidence: High - full enabled checks completed.'
    }

    $groupLines = @(
        'P0:'
    )
    $groupLines += if ($OperatorData.p0.Count -gt 0) { $OperatorData.p0 | ForEach-Object { "- $_" } } else { '- none' }
    $groupLines += 'P1:'
    $groupLines += if ($OperatorData.p1.Count -gt 0) { $OperatorData.p1 | ForEach-Object { "- $_" } } else { '- none' }
    $groupLines += 'P2:'
    $groupLines += if ($OperatorData.p2.Count -gt 0) { $OperatorData.p2 | ForEach-Object { "- $_" } } else { '- none' }

    $priorityActionsLines = @(
        'SITE_AUDITOR PRIORITY ACTIONS',
        "OVERALL: $($Assembled.overall_status)",
        "CORE_PROBLEM: $($OperatorData.core_problem)",
        $confidence,
        '',
        'PRIORITY_GROUPS'
    ) + $groupLines + @(
        '',
        'DO_NEXT'
    ) + ($OperatorData.do_next | ForEach-Object { "- $_" })

    $topIssuesLines = @(
        'SITE_AUDITOR TOP ISSUES',
        "CORE_PROBLEM: $($OperatorData.core_problem)",
        ''
    ) + $groupLines

    $summaryLines = @(
        'SITE_AUDITOR EXECUTIVE SUMMARY',
        "GENERATED: $($Assembled.generated_at)",
        "OVERALL_STATUS: $($Assembled.overall_status)",
        "CORE_PROBLEM: $($OperatorData.core_problem)",
        $confidence,
        '',
        'DO_NEXT (max 3)'
    ) + ($OperatorData.do_next | ForEach-Object { "- $_" }) + @(
        '',
        "DETAILS: $($OperatorData.outbox_dir)/REPORT.txt",
        "SOURCE_REPORTS: $($OperatorData.reports_dir)",
        "ANALYST_HANDOFF: $($OperatorData.reports_dir)/12A_META_AUDIT_BRIEF.txt"
    )

    $priorityActionsLines | Out-File -FilePath (Join-Path $bundleRoot '00_PRIORITY_ACTIONS.txt') -Encoding utf8
    $topIssuesLines | Out-File -FilePath (Join-Path $bundleRoot '01_TOP_ISSUES.txt') -Encoding utf8
    $summaryLines | Out-File -FilePath (Join-Path $bundleRoot '11A_EXECUTIVE_SUMMARY.txt') -Encoding utf8
    Copy-Item -Path (Join-Path $OperatorData.reports_dir '12A_META_AUDIT_BRIEF.txt') -Destination (Join-Path $bundleRoot '12A_META_AUDIT_BRIEF.txt') -Force -ErrorAction SilentlyContinue

    Add-ExecutionLog 'OPERATOR_FILES_WRITTEN=00_PRIORITY_ACTIONS.txt,01_TOP_ISSUES.txt,11A_EXECUTIVE_SUMMARY.txt,12A_META_AUDIT_BRIEF.txt'
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
    $lines.Add('OPERATOR PRIORITY ACTIONS: audit_bundle/00_PRIORITY_ACTIONS.txt')
    $lines.Add('OPERATOR TOP ISSUES: audit_bundle/01_TOP_ISSUES.txt')
    $lines.Add('OPERATOR EXECUTIVE SUMMARY: audit_bundle/11A_EXECUTIVE_SUMMARY.txt')
    $lines.Add('ANALYST HANDOFF BRIEF: audit_bundle/12A_META_AUDIT_BRIEF.txt')
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
    $Assembled.bundle_status.repo.artifacts = @()
    foreach ($item in $repoScreenshotManifest) {
        $Assembled.bundle_status.repo.artifacts += [string]$item.relative_path
    }

    try {
        $assembled.bundle_status | ConvertTo-Json -Depth 6 | Out-File -FilePath $bundleStatusPath -Encoding utf8
        $assembled | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding utf8
        $operatorData = New-OperatorReportData -Assembled $Assembled
        Write-OperatorBundleFiles -Assembled $Assembled -OperatorData $operatorData
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

    if ($null -eq $r) {
        return @{
            status = 'FAIL'
            reason = "${name}_NULL_RESULT"
        }
    }

    $readProperty = {
        param($obj, [string]$propName)

        if ($obj -is [hashtable]) {
            if ($obj.Contains($propName)) {
                return $obj[$propName]
            }

            return $null
        }

        if ($null -ne $obj.PSObject -and $null -ne $obj.PSObject.Properties[$propName]) {
            return $obj.PSObject.Properties[$propName].Value
        }

        return $null
    }

    $screenshotsCountRaw = & $readProperty $r 'screenshots_count'
    $reportsPathRaw = & $readProperty $r 'reports_path'
    $outboxPathRaw = & $readProperty $r 'outbox_path'
    $statusRaw = & $readProperty $r 'status'
    $reasonRaw = & $readProperty $r 'reason'

    $screenshotsCount = 0
    if ($null -ne $screenshotsCountRaw) {
        [void][int]::TryParse([string]$screenshotsCountRaw, [ref]$screenshotsCount)
    }

    $hasReportsPath = -not [string]::IsNullOrWhiteSpace([string]$reportsPathRaw)
    $hasOutboxPath = -not [string]::IsNullOrWhiteSpace([string]$outboxPathRaw)

    $hasData =
        ($screenshotsCount -gt 0) -or
        $hasReportsPath -or
        $hasOutboxPath

    if ($name -eq 'repo') {
        Write-Output "REPO_HAS_DATA=$hasData"
        Write-Output ("ORIGINAL_OBJECT=" + ($r | ConvertTo-Json -Depth 5 -Compress))
    }

    $status = if ($null -ne $statusRaw) { [string]$statusRaw } else { '' }
    $reason = if ($null -ne $reasonRaw) { [string]$reasonRaw } else { '' }

    if (-not $status) {
        if ($hasData) {
            $status = 'PARTIAL'
            $reason = "${name}_COERCED_FROM_DATA"
        }
        else {
            $status = 'FAIL'
            $reason = "${name}_INVALID_RESULT"
        }
    }

    if ($name -eq 'repo') {
        Write-Output "NORMALIZED_STATUS=$status"
    }

    return @{
        status = $status
        reason = $reason
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

Write-Output ($repo | ConvertTo-Json -Depth 5)

$repo = Normalize-Result $repo 'repo'
$zip = Normalize-Result $zip 'zip'
$url = Normalize-Result $url 'url'

$manifest = @{
    overall = [string]$overall
    repo = $repo
    zip = $zip
    url = $url
}

$manifest_json = $manifest | ConvertTo-Json -Depth 5
Write-Output $manifest_json | Out-File -FilePath $summaryPath -Encoding utf8
Write-Output $manifest_json | Out-File -FilePath $bundleStatusPath -Encoding utf8
Add-ExecutionLog 'MANIFEST_OUTPUT_JSON_OK'
Write-Output $manifest_json
exit $exitCode
