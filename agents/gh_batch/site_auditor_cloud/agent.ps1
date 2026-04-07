param(
    [string]$MODE = 'REPO'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
$outboxDir = Join-Path $base 'outbox'
$reportsDir = Join-Path $base 'reports'
$timestamp = (Get-Date).ToString('o')
$status = 'FAIL'
$reportLines = New-Object System.Collections.Generic.List[string]
$reportFiles = New-Object System.Collections.Generic.List[string]
$auditData = @{}

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding utf8
}

function Add-ReportLine([string]$Text) {
    $script:reportLines.Add($Text)
}

function Write-TextFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $Lines -join "`n" | Out-File -FilePath $Path -Encoding utf8
}

Ensure-Dir $outboxDir
Ensure-Dir $reportsDir

Add-ReportLine "MODE: $MODE"
Add-ReportLine "TIMESTAMP: $timestamp"

try {
    switch ($MODE.ToUpperInvariant()) {
        'REPO' {
            $targetRepo = $env:TARGET_REPO_PATH
            $bound = -not [string]::IsNullOrWhiteSpace($targetRepo) -and (Test-Path $targetRepo -PathType Container)

            if (-not $bound) {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine 'REASON: TARGET_REPO_PATH is missing or invalid.'
                $auditData = @{
                    mode = 'REPO'
                    target_repo_bound = $false
                    repo_root = $targetRepo
                    inventory = @{}
                    findings = @('Could not bind TARGET_REPO_PATH to an existing directory.')
                }
                throw 'REPO mode cannot continue without TARGET_REPO_PATH.'
            }

            $repoRoot = (Resolve-Path $targetRepo).Path
            $allFiles = Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue
            $topDirs = Get-ChildItem -Path $repoRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            $extBreakdown = $allFiles |
                Group-Object { if ([string]::IsNullOrWhiteSpace($_.Extension)) { '[none]' } else { $_.Extension.ToLowerInvariant() } } |
                Sort-Object Count -Descending |
                Select-Object -First 15 |
                ForEach-Object {
                    [PSCustomObject]@{
                        extension = $_.Name
                        count = $_.Count
                    }
                }

            $readmeExists = Test-Path (Join-Path $repoRoot 'README.md')
            $findings = New-Object System.Collections.Generic.List[string]
            if (-not $readmeExists) { $findings.Add('README.md is missing at repository root.') }
            if ($allFiles.Count -eq 0) { $findings.Add('Repository has zero files in inventory scan.') }

            $auditData = @{
                mode = 'REPO'
                target_repo_bound = $true
                repo_root = $repoRoot
                inventory = @{
                    file_count = $allFiles.Count
                    top_level_directories = $topDirs
                    extension_breakdown = $extBreakdown
                    has_readme = $readmeExists
                }
                findings = $findings
            }

            if ($allFiles.Count -gt 0) {
                $status = 'PASS'
                Add-ReportLine 'STATUS: PASS'
                Add-ReportLine "REPO ROOT: $repoRoot"
                Add-ReportLine "FILES SCANNED: $($allFiles.Count)"
            } else {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine 'REASON: Inventory scan returned zero files.'
            }
        }
        'URL' {
            $baseUrl = $env:BASE_URL
            if ([string]::IsNullOrWhiteSpace($baseUrl)) {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine 'REASON: BASE_URL is required for URL mode.'
                $auditData = @{
                    mode = 'URL'
                    base_url = $baseUrl
                    routes = @()
                    findings = @('BASE_URL was not provided.')
                }
                throw 'URL mode missing BASE_URL.'
            }

            $captureScript = Join-Path $base 'capture.mjs'
            if (-not (Test-Path $captureScript -PathType Leaf)) {
                throw 'capture.mjs not found.'
            }

            $env:REPORTS_DIR = $reportsDir
            $captureOutput = & node $captureScript 2>&1
            if ($LASTEXITCODE -ne 0) {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine 'REASON: capture.mjs execution failed.'
                Add-ReportLine ($captureOutput -join "`n")
                $auditData = @{
                    mode = 'URL'
                    base_url = $baseUrl
                    routes = @()
                    findings = @('capture.mjs failed to execute successfully.')
                }
                throw 'capture.mjs failed.'
            }

            $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
            if (-not (Test-Path $visualManifestPath -PathType Leaf)) {
                throw 'visual_manifest.json was not generated by capture.mjs.'
            }

            $routes = Get-Content -Path $visualManifestPath -Raw | ConvertFrom-Json
            $errored = @($routes | Where-Object { $_.status -eq 'error' -or ([int]$_.status -ge 400) })
            $healthy = @($routes | Where-Object { $_.status -ne 'error' -and ([int]$_.status -lt 400) })
            $totalShots = ($routes | Measure-Object -Property screenshotCount -Sum).Sum
            if ($null -eq $totalShots) { $totalShots = 0 }

            $findings = New-Object System.Collections.Generic.List[string]
            if ($errored.Count -gt 0) { $findings.Add("$($errored.Count) route(s) returned errors or HTTP >= 400.") }
            if ($totalShots -eq 0) { $findings.Add('No screenshots were captured.') }

            $auditData = @{
                mode = 'URL'
                base_url = $baseUrl
                routes = $routes
                route_summary = @{
                    total_routes = @($routes).Count
                    healthy_routes = $healthy.Count
                    error_routes = $errored.Count
                    screenshot_count = $totalShots
                }
                findings = $findings
            }

            if (@($routes).Count -gt 0 -and $errored.Count -eq 0 -and $totalShots -gt 0) {
                $status = 'PASS'
                Add-ReportLine 'STATUS: PASS'
                Add-ReportLine "BASE URL: $baseUrl"
                Add-ReportLine "ROUTES AUDITED: $(@($routes).Count)"
                Add-ReportLine "SCREENSHOTS: $totalShots"
            } else {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine "BASE URL: $baseUrl"
                Add-ReportLine "ROUTES AUDITED: $(@($routes).Count)"
                Add-ReportLine "ERROR ROUTES: $($errored.Count)"
                Add-ReportLine "SCREENSHOTS: $totalShots"
            }
        }
        'ZIP' {
            $zipPath = & (Join-Path $base 'lib/intake_zip.ps1') -InboxPath (Join-Path $base 'input/inbox')
            if ([string]::IsNullOrWhiteSpace($zipPath)) {
                Add-ReportLine 'STATUS: FAIL'
                Add-ReportLine 'REASON: No ZIP payload found in input/inbox.'
                $auditData = @{
                    mode = 'ZIP'
                    target_repo_bound = $false
                    zip_payload = $null
                    findings = @('No ZIP file detected in input/inbox.')
                }
                throw 'ZIP mode found no input payload.'
            }

            & (Join-Path $base 'lib/preflight.ps1') -ZipPath $zipPath | Out-Null
            $zipInfo = Get-Item $zipPath
            $auditData = @{
                mode = 'ZIP'
                target_repo_bound = $true
                zip_payload = @{
                    path = $zipInfo.FullName
                    name = $zipInfo.Name
                    size_bytes = $zipInfo.Length
                    last_write_time = $zipInfo.LastWriteTimeUtc.ToString('o')
                }
                findings = @('ZIP payload validated; downstream extraction is not implemented in this agent.')
            }
            $status = 'PASS'
            Add-ReportLine 'STATUS: PASS'
            Add-ReportLine "ZIP PAYLOAD: $($zipInfo.FullName)"
        }
        default {
            Add-ReportLine 'STATUS: FAIL'
            Add-ReportLine "REASON: Unsupported mode '$MODE'."
            $auditData = @{
                mode = $MODE
                findings = @("Unsupported mode '$MODE'.")
            }
            throw "Unsupported mode: $MODE"
        }
    }
}
catch {
    if ($status -ne 'PASS') { $status = 'FAIL' }
    Add-ReportLine "ERROR: $($_.Exception.Message)"
}

$auditResultPath = Join-Path $reportsDir 'audit_result.json'
Write-JsonFile -Path $auditResultPath -Data @{
    status = $status
    timestamp = $timestamp
    data = $auditData
}
$reportFiles.Add('reports/audit_result.json')

$topIssues = @()
if ($auditData.ContainsKey('findings')) {
    $topIssues = @($auditData.findings)
}
if ($topIssues.Count -eq 0) {
    $topIssues = @('No high-priority issues detected from collected data.')
}

$priorityActions = @(
    "1) Confirm mode-specific inputs are present (MODE=$MODE).",
    '2) Review audit_result.json and route/inventory evidence for next fixes.',
    '3) Re-run SITE_AUDITOR after addressing top issues.'
)
if ($status -eq 'FAIL') {
    $priorityActions = @(
        '1) Resolve the explicit failure reason documented in REPORT.txt.',
        '2) Verify required environment variables and runtime dependencies.',
        '3) Re-run and confirm DONE.ok is produced.'
    )
}

$howToFix = @{
    mode = $MODE
    status = $status
    generated_from = 'audit_result.json'
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

$summaryLines = @(
    "SITE_AUDITOR EXECUTIVE SUMMARY",
    "Mode: $MODE",
    "Status: $status",
    "Generated: $timestamp",
    "Primary evidence: reports/audit_result.json"
)
$summaryPath = Join-Path $reportsDir '11A_EXECUTIVE_SUMMARY.txt'
Write-TextFile -Path $summaryPath -Lines $summaryLines
$reportFiles.Add('reports/11A_EXECUTIVE_SUMMARY.txt')

$manifest = @{
    mode = $MODE
    status = $status
    repo_root = if ($auditData.ContainsKey('repo_root')) { $auditData.repo_root } else { $null }
    target_repo_bound = if ($auditData.ContainsKey('target_repo_bound')) { [bool]$auditData.target_repo_bound } else { $false }
    output_root = $base
    report_files = $reportFiles
    timestamp = $timestamp
}
$reportFiles.Add('reports/run_manifest.json')
$manifestPath = Join-Path $reportsDir 'run_manifest.json'
Write-JsonFile -Path $manifestPath -Data $manifest

$reportPath = Join-Path $outboxDir 'REPORT.txt'
if ($reportLines.Count -eq 0) {
    $reportLines.Add("MODE: $MODE")
    $reportLines.Add("STATUS: $status")
}
$reportLines.Add("MANIFEST: reports/run_manifest.json")
Write-TextFile -Path $reportPath -Lines $reportLines

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
