# RUN_BATCH_v3_TARGET_LOCK.ps1

param(
    [string]$ZipPath,
    [string]$LogsDir
)

$ErrorActionPreference = 'Stop'

$result = @{
    status = 'PASS'
    reason_code = ''
    message = ''
    apply_changed = $false
    expected_repo = $env:EXPECTED_REPO
    effective_repo = $env:GITHUB_REPOSITORY
    expected_branch = $env:EXPECTED_BRANCH
    effective_branch = $env:GITHUB_REF
}

# =========================
# TARGET VALIDATION (P0)
# =========================

if ($env:GITHUB_REPOSITORY -ne $env:EXPECTED_REPO) {
    $result.status = 'FAIL_POLICY'
    $result.reason_code = 'FAIL_WRONG_TARGET_REPO'
    $result.message = "Wrong repo: $($env:GITHUB_REPOSITORY)"
}

if ($env:GITHUB_REF -notlike "*$($env:EXPECTED_BRANCH)") {
    $result.status = 'FAIL_POLICY'
    $result.reason_code = 'FAIL_WRONG_TARGET_BRANCH'
    $result.message = "Wrong branch: $($env:GITHUB_REF)"
}

if ($result.status -ne 'PASS') {
    $reportPath = Join-Path $LogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
    $result | ConvertTo-Json -Depth 5 | Set-Content $reportPath
    throw "TARGET VALIDATION FAILED"
}

# =========================
# ORIGINAL LOGIC
# =========================

$temp = Join-Path $env:TEMP ("ghb_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $temp | Out-Null

Expand-Archive -Path $ZipPath -DestinationPath $temp -Force

$root = $temp

$items = Get-ChildItem $temp
if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
    $root = $items[0].FullName
}

$srcCandidate = Get-ChildItem -Path $root -Recurse -Directory | Where-Object { $_.Name -eq 'src' } | Select-Object -First 1
if ($srcCandidate) {
    $root = $srcCandidate.FullName
}

$files = Get-ChildItem -Path $root -Recurse -File

if ($files.Count -eq 0) {
    $result.status = 'FAIL_POLICY'
    $result.reason_code = 'EMPTY_ZIP'
    $result.message = 'No files found in ZIP'
}

$repoRoot = $env:GITHUB_WORKSPACE

foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).TrimStart("\\/")
    $target = Join-Path $repoRoot $rel

    $dir = Split-Path $target
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    Copy-Item $f.FullName $target -Force
    $result.apply_changed = $true
}

$reportPath = Join-Path $LogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
$result | ConvertTo-Json -Depth 5 | Set-Content $reportPath

Write-Output "DONE"
