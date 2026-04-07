param(
    [string]$MODE = 'REPO'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
$outboxDir = Join-Path $base 'outbox'
$reportsDir = Join-Path $base 'reports'
$runtimeDir = Join-Path $base 'runtime'
$zipWorkRoot = Join-Path $runtimeDir 'zip_extracted'
$timestamp = (Get-Date).ToString('o')
$status = 'FAIL'
$reportFiles = New-Object System.Collections.Generic.List[string]

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Reset-Dir([string]$Path) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    $Data | ConvertTo-Json -Depth 20 | Out-File -FilePath $Path -Encoding utf8
}

function Write-TextFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $Lines -join "`n" | Out-File -FilePath $Path -Encoding utf8
}

function Get-SourceSummary {
    param([string]$Root)

    $allFiles = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue)
    $topDirs = @(Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $extBreakdown = @(
        $allFiles |
            Group-Object { if ([string]::IsNullOrWhiteSpace($_.Extension)) { '[none]' } else { $_.Extension.ToLowerInvariant() } } |
            Sort-Object Count -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                [PSCustomObject]@{
                    extension = $_.Name
                    count = $_.Count
                }
            }
    )

    $readmeCandidates = @('README.md', 'README', 'readme.md', 'Readme.md')
    $hasReadme = $false
    foreach ($candidate in $readmeCandidates) {
        if (Test-Path (Join-Path $Root $candidate) -PathType Leaf) {
            $hasReadme = $true
            break
        }
    }

    $findings = New-Object System.Collections.Generic.List[string]
    if ($allFiles.Count -eq 0) { $findings.Add('Source inventory returned zero files.') }
    if (-not $hasReadme) { $findings.Add('No README marker found at source root.') }

    return @{
        summary = @{
            file_count = $allFiles.Count
            top_level_directories = $topDirs
            extension_breakdown = $extBreakdown
            has_readme = $hasReadme
        }
        findings = @($findings)
    }
}

function Invoke-SourceAuditRepo {
    param([string]$TargetRepoPath)

    if ([string]::IsNullOrWhiteSpace($TargetRepoPath) -or -not (Test-Path $TargetRepoPath -PathType Container)) {
        throw 'TARGET_REPO_PATH is missing or invalid for REPO mode.'
    }

    $repoRoot = (Resolve-Path $TargetRepoPath).Path
    $sourceData = Get-SourceSummary -Root $repoRoot

    return @{
        enabled = $true
        kind = 'repo'
        root = $repoRoot
        extracted_root = $null
        summary = $sourceData.summary
        findings = $sourceData.findings
        ok = ($sourceData.summary.file_count -gt 0)
    }
}

function Invoke-SourceAuditZip {
    param([string]$InboxPath)

    $zipPath = & (Join-Path $base 'lib/intake_zip.ps1') -InboxPath $InboxPath
    if ([string]::IsNullOrWhiteSpace($zipPath)) {
        throw 'Missing required input: ZIP payload in input/inbox for ZIP mode.'
    }

    & (Join-Path $base 'lib/preflight.ps1') -ZipPath $zipPath | Out-Null

    Reset-Dir -Path $zipWorkRoot

    try {
        Expand-Archive -Path $zipPath -DestinationPath $zipWorkRoot -Force
    }
    catch {
        throw "ZIP extraction failed: $($_.Exception.Message)"
    }

    $inventoryFiles = @(Get-ChildItem -Path $zipWorkRoot -Recurse -File -ErrorAction Stop)
    if ($inventoryFiles.Count -eq 0) {
        throw 'ZIP extraction completed but no files were found in extracted content.'
    }

    $sourceData = Get-SourceSummary -Root $zipWorkRoot

    $zipInfo = Get-Item -Path $zipPath
    return @{
        enabled = $true
        kind = 'zip'
        root = $zipInfo.FullName
        extracted_root = $zipWorkRoot
        zip_payload = @{
            path = $zipInfo.FullName
            name = $zipInfo.Name
            size_bytes = $zipInfo.Length
            last_write_time = $zipInfo.LastWriteTimeUtc.ToString('o')
        }
        summary = $sourceData.summary
        findings = $sourceData.findings
        ok = ($sourceData.summary.file_count -gt 0)
    }
}

function Invoke-LiveAudit {
    param([string]$BaseUrl)

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return @{
            enabled = $false
            base_url = $null
            summary = @{}
            findings = @('BASE_URL was not provided; live audit disabled.')
            warnings = @('Live audit skipped because BASE_URL is missing.')
            ok = $true
        }
    }

    $captureScript = Join-Path $base 'capture.mjs'
    if (-not (Test-Path $captureScript -PathType Leaf)) {
        throw 'capture.mjs not found.'
    }

    $env:REPORTS_DIR = $reportsDir
    $captureOutput = & node $captureScript 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "capture.mjs execution failed: $($captureOutput -join ' | ')"
    }

    $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
    if (-not (Test-Path $visualManifestPath -PathType Leaf)) {
        throw 'visual_manifest.json was not generated by capture.mjs.'
    }

    $routes = @(Get-Content -Path $visualManifestPath -Raw | ConvertFrom-Json)
    $errored = @($routes | Where-Object { $_.status -eq 'error' -or ([int]$_.status -ge 400) })
    $healthy = @($routes | Where-Object { $_.status -ne 'error' -and ([int]$_.status -lt 400) })
    $totalShots = ($routes | Measure-Object -Property screenshotCount -Sum).Sum
    if ($null -eq $totalShots) { $totalShots = 0 }

    $findings = New-Object System.Collections.Generic.List[string]
    if ($errored.Count -gt 0) { $findings.Add("$($errored.Count) route(s) returned errors or HTTP >= 400.") }
    if ($totalShots -eq 0) { $findings.Add('No screenshots were captured.') }
    if (@($routes).Count -eq 0) { $findings.Add('visual_manifest.json has zero routes.') }

    return @{
        enabled = $true
        base_url = $BaseUrl
        summary = @{
            total_routes = @($routes).Count
            healthy_routes = $healthy.Count
            error_routes = $errored.Count
            screenshot_count = [int]$totalShots
        }
        findings = @($findings)
        warnings = @()
        ok = (@($routes).Count -gt 0 -and $errored.Count -eq 0 -and [int]$totalShots -gt 0)
    }
}

function Build-DecisionLayer {
    param(
        [string]$ResolvedMode,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [string[]]$MissingInputs,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $p0 = New-Object System.Collections.Generic.List[string]
    $p1 = New-Object System.Collections.Generic.List[string]
    $p2 = New-Object System.Collections.Generic.List[string]
    $doNext = New-Object System.Collections.Generic.List[string]

    foreach ($missing in @($MissingInputs)) {
        $p0.Add("Missing required input: $missing")
    }

    if ($ResolvedMode -in @('REPO', 'ZIP') -and $SourceLayer.required) {
        if (-not $SourceLayer.enabled -or -not $SourceLayer.ok) {
            $p0.Add("Source audit failure in $ResolvedMode mode.")
        }
    }

    if ($LiveLayer.required -and (-not $LiveLayer.enabled -or -not $LiveLayer.ok)) {
        $p0.Add("Live audit failure in $ResolvedMode mode.")
    }

    foreach ($warning in $Warnings) {
        $p1.Add($warning)
    }

    if ($SourceLayer.enabled -and $SourceLayer.summary.file_count -gt 0 -and ($SourceLayer.findings | Measure-Object).Count -eq 0) {
        $p2.Add('Source structure baseline looks healthy from inventory scan.')
    }

    if ($LiveLayer.enabled -and $LiveLayer.ok) {
        $p2.Add('Live route capture completed with healthy status codes and screenshots.')
    }

    if ($p0.Count -gt 0) {
        $core = $p0[0]
        $doNext.Add('Resolve all P0 items before re-running SITE_AUDITOR.')
    } elseif ($p1.Count -gt 0) {
        $core = $p1[0]
        $doNext.Add('Address P1 warnings to move from partial to complete audit coverage.')
    } else {
        if ($ResolvedMode -in @('REPO', 'ZIP')) {
            $core = "Combined source + live audit succeeded for $ResolvedMode mode."
        } else {
            $core = 'Live URL audit succeeded for URL mode.'
        }
        $doNext.Add('Proceed with normal remediation planning using low-priority findings.')
    }

    if ($LiveLayer.enabled) {
        $doNext.Add('Review reports/visual_manifest.json and screenshots for route-level detail.')
    }

    if ($SourceLayer.enabled) {
        $doNext.Add('Review source summary metrics and extension breakdown for cleanup opportunities.')
    }

    return @{
        core_problem = $core
        p0 = @($p0)
        p1 = @($p1)
        p2 = @($p2)
        do_next = @($doNext)
    }
}

function Write-OperatorOutputs {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [hashtable]$AuditResult,
        [hashtable]$Decision
    )

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    Write-JsonFile -Path $auditResultPath -Data $AuditResult
    $reportFiles.Add('reports/audit_result.json')

    $topIssues = @($Decision.p0 + $Decision.p1)
    if ($topIssues.Count -eq 0) {
        $topIssues = @($Decision.p2)
    }
    if ($topIssues.Count -eq 0) {
        $topIssues = @('No major issues detected from collected source/live evidence.')
    }

    $priorityActions = @()
    if ($FinalStatus -eq 'FAIL') {
        $priorityActions += '1) Resolve P0 failures first and rerun the same MODE.'
        $priorityActions += '2) Validate required inputs (TARGET_REPO_PATH, ZIP payload, BASE_URL) for the selected MODE.'
        $priorityActions += '3) Confirm reports/audit_result.json and REPORT.txt reflect non-empty evidence.'
    } else {
        $priorityActions += '1) Execute do_next items to improve quality and reduce latent risk.'
        $priorityActions += '2) Track P1/P2 findings in the remediation backlog.'
        $priorityActions += '3) Re-run SITE_AUDITOR after major content or route changes.'
    }

    $howToFix = @{
        mode = $ResolvedMode
        status = $FinalStatus
        generated_from = 'audit_result.json'
        core_problem = $Decision.core_problem
        top_issues = $topIssues
        priority_actions = $priorityActions
    }
    $howToFixPath = Join-Path $reportsDir 'HOW_TO_FIX.json'
    Write-JsonFile -Path $howToFixPath -Data $howToFix
    $reportFiles.Add('reports/HOW_TO_FIX.json')

    $priorityPath = Join-Path $reportsDir '00_PRIORITY_ACTIONS.txt'
    Write-TextFile -Path $priorityPath -Lines $priorityActions
    $reportFiles.Add('reports/00_PRIORITY_ACTIONS.txt')

    $issuesPath = Join-Path $reportsDir '01_TOP_ISSUES.txt'
    Write-TextFile -Path $issuesPath -Lines $topIssues
    $reportFiles.Add('reports/01_TOP_ISSUES.txt')

    $sourceStatus = if (-not $AuditResult.source.enabled) { 'OFF' } elseif ($AuditResult.source.ok) { 'PASS' } else { 'FAIL' }
    $liveStatus = if (-not $AuditResult.live.enabled) { 'OFF' } elseif ($AuditResult.live.ok) { 'PASS' } else { 'FAIL' }
    $requiredInputsLine = if ($AuditResult.required_inputs.Count -gt 0) { $AuditResult.required_inputs -join ', ' } else { 'none' }

    $summaryLines = @(
        'SITE_AUDITOR EXECUTIVE SUMMARY',
        "Mode: $ResolvedMode",
        "Status: $FinalStatus",
        "Required inputs: $requiredInputsLine",
        "Source audit: $sourceStatus",
        "Live audit: $liveStatus",
        "Core problem: $($Decision.core_problem)",
        "Generated: $timestamp",
        'Primary evidence: reports/audit_result.json'
    )
    $summaryPath = Join-Path $reportsDir '11A_EXECUTIVE_SUMMARY.txt'
    Write-TextFile -Path $summaryPath -Lines $summaryLines
    $reportFiles.Add('reports/11A_EXECUTIVE_SUMMARY.txt')

    $reportLines = @(
        "MODE: $ResolvedMode",
        "REQUIRED INPUTS: $requiredInputsLine",
        "SOURCE AUDIT: $sourceStatus",
        "LIVE AUDIT: $liveStatus",
        "OVERALL STATUS: $FinalStatus",
        "CORE PROBLEM: $($Decision.core_problem)",
        'P0:'
    )
    $reportLines += if ($Decision.p0.Count -gt 0) { $Decision.p0 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'P1:'
    $reportLines += if ($Decision.p1.Count -gt 0) { $Decision.p1 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'P2:'
    $reportLines += if ($Decision.p2.Count -gt 0) { $Decision.p2 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'DO NEXT:'
    $reportLines += if ($Decision.do_next.Count -gt 0) { $Decision.do_next | ForEach-Object { "- $_" } } else { '- none' }

    $manifest = @{
        mode = $ResolvedMode
        status = $FinalStatus
        repo_root = $AuditResult.source.root
        target_repo_bound = [bool]($AuditResult.source.enabled)
        output_root = $base
        report_files = @($reportFiles)
        timestamp = $timestamp
    }

    $manifestPath = Join-Path $reportsDir 'run_manifest.json'
    Write-JsonFile -Path $manifestPath -Data $manifest
    $reportFiles.Add('reports/run_manifest.json')
    $reportLines += 'MANIFEST: reports/run_manifest.json'

    $reportPath = Join-Path $outboxDir 'REPORT.txt'
    Write-TextFile -Path $reportPath -Lines $reportLines
}

Ensure-Dir $outboxDir
Ensure-Dir $reportsDir
Ensure-Dir $runtimeDir

$resolvedMode = $MODE.ToUpperInvariant()
$warnings = New-Object System.Collections.Generic.List[string]
$requiredInputs = @()
$missingInputs = New-Object System.Collections.Generic.List[string]
$sourceLayer = @{ enabled = $false; required = $false; kind = $null; root = $null; extracted_root = $null; base_url = $null; summary = @{}; findings = @(); ok = $false }
$liveLayer = @{ enabled = $false; required = $false; root = $null; base_url = $null; summary = @{}; findings = @(); warnings = @(); ok = $false }

try {
    switch ($resolvedMode) {
        'REPO' {
            $requiredInputs = @('TARGET_REPO_PATH', 'BASE_URL')
            $sourceLayer.required = $true
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH)) { $missingInputs.Add('TARGET_REPO_PATH') }
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for REPO mode: " + ($missingInputs -join ', ')) }
            $sourceLayer = Invoke-SourceAuditRepo -TargetRepoPath $env:TARGET_REPO_PATH
            $sourceLayer.required = $true
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        'ZIP' {
            $requiredInputs = @('ZIP payload in input/inbox', 'BASE_URL')
            $sourceLayer.required = $true
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for ZIP mode: " + ($missingInputs -join ', ')) }
            $sourceLayer = Invoke-SourceAuditZip -InboxPath (Join-Path $base 'input/inbox')
            $sourceLayer.required = $true
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        'URL' {
            $requiredInputs = @('BASE_URL')
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for URL mode: " + ($missingInputs -join ', ')) }
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        default {
            throw "Unsupported mode: $MODE"
        }
    }

    foreach ($lw in @($liveLayer.warnings)) { $warnings.Add($lw) }

    $decision = Build-DecisionLayer -ResolvedMode $resolvedMode -SourceLayer $sourceLayer -LiveLayer $liveLayer -MissingInputs @($missingInputs) -Warnings $warnings

    $status = 'PASS'
    if ($missingInputs.Count -gt 0) { $status = 'FAIL' }
    if ($sourceLayer.required -and (-not $sourceLayer.enabled -or -not $sourceLayer.ok)) { $status = 'FAIL' }
    if ($liveLayer.required -and (-not $liveLayer.enabled -or -not $liveLayer.ok)) { $status = 'FAIL' }

    $auditResult = @{
        status = $status
        timestamp = $timestamp
        mode = $resolvedMode
        required_inputs = $requiredInputs
        source = @{
            enabled = [bool]$sourceLayer.enabled
            required = [bool]$sourceLayer.required
            ok = [bool]$sourceLayer.ok
            kind = $sourceLayer.kind
            root = $sourceLayer.root
            extracted_root = $sourceLayer.extracted_root
            base_url = $sourceLayer.base_url
            summary = $sourceLayer.summary
            findings = @($sourceLayer.findings)
        }
        live = @{
            enabled = [bool]$liveLayer.enabled
            required = [bool]$liveLayer.required
            ok = [bool]$liveLayer.ok
            root = $liveLayer.root
            base_url = $liveLayer.base_url
            summary = $liveLayer.summary
            findings = @($liveLayer.findings)
        }
        decision = $decision
    }

    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus $status -AuditResult $auditResult -Decision $decision
}
catch {
    $status = 'FAIL'

    $failureReason = $_.Exception.Message
    if (-not $failureReason) { $failureReason = 'Unknown failure while running SITE_AUDITOR.' }

    $decision = @{
        core_problem = $failureReason
        p0 = @($failureReason)
        p1 = @($warnings)
        p2 = @()
        do_next = @('Resolve the failure reason and rerun SITE_AUDITOR.')
    }

    $auditResult = @{
        status = 'FAIL'
        timestamp = $timestamp
        mode = $resolvedMode
        required_inputs = $requiredInputs
        source = @{
            enabled = [bool]$sourceLayer.enabled
            required = [bool]$sourceLayer.required
            ok = [bool]$sourceLayer.ok
            kind = $sourceLayer.kind
            root = $sourceLayer.root
            extracted_root = $sourceLayer.extracted_root
            base_url = $sourceLayer.base_url
            summary = $sourceLayer.summary
            findings = @($sourceLayer.findings)
        }
        live = @{
            enabled = [bool]$liveLayer.enabled
            required = [bool]$liveLayer.required
            ok = [bool]$liveLayer.ok
            root = $liveLayer.root
            base_url = $liveLayer.base_url
            summary = $liveLayer.summary
            findings = @($liveLayer.findings)
        }
        decision = $decision
    }

    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus 'FAIL' -AuditResult $auditResult -Decision $decision
}

$doneOk = Join-Path $outboxDir 'DONE.ok'
$doneFail = Join-Path $outboxDir 'DONE.fail'
if (Test-Path $doneOk) { Remove-Item $doneOk -Force }
if (Test-Path $doneFail) { Remove-Item $doneFail -Force }

if ($status -eq 'PASS') {
    New-Item -ItemType File -Path $doneOk -Force | Out-Null
    Write-Host "SITE_AUDITOR completed successfully. Artifacts: $outboxDir ; $reportsDir"
    exit 0
}

New-Item -ItemType File -Path $doneFail -Force | Out-Null
Write-Host "SITE_AUDITOR failed. Artifacts: $outboxDir ; $reportsDir"
exit 1
