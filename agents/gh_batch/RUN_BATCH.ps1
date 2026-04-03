# RUN_BATCH.ps1 — FIXED v2 (target repo + PS-safe paths)

param(
    [string]$ZipPath,
    [string]$LogsDir
)

$ErrorActionPreference = 'Stop'

function Write-Report {
    param($result)
    if (!(Test-Path $LogsDir)) {
        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    }
    $reportPath = Join-Path $LogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
    $result | ConvertTo-Json -Depth 10 | Set-Content $reportPath
}

# =========================
# INIT RESULT
# =========================

$result = @{
    status = 'PASS'
    reason_code = ''
    message = ''
    apply_changed = $false

    expected_repo   = $env:EXPECTED_REPO
    effective_repo  = $env:GITHUB_REPOSITORY
    expected_branch = $env:EXPECTED_BRANCH
    effective_branch= $env:GITHUB_REF
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
    Write-Report $result
    throw "TARGET VALIDATION FAILED"
}

# =========================
# PATH RESOLVE
# =========================

$targetRepoPath = $env:TARGET_REPO_PATH
if (-not $targetRepoPath -or !(Test-Path $targetRepoPath)) {
    $result.status = 'FAIL_RUNTIME'
    $result.reason_code = 'TARGET_REPO_PATH_INVALID'
    $result.message = "TARGET_REPO_PATH not found"
    Write-Report $result
    throw "TARGET PATH ERROR"
}

# =========================
# UNZIP
# =========================

$temp = Join-Path $env:TEMP ("ghb_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $temp | Out-Null

Expand-Archive -Path $ZipPath -DestinationPath $temp -Force

$root = $temp

# unwrap single folder
$items = Get-ChildItem $temp
if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
    $root = $items[0].FullName
}

# find src if exists
$srcCandidate = Get-ChildItem -Path $root -Recurse -Directory |
    Where-Object { $_.Name -eq 'src' } |
    Select-Object -First 1

if ($srcCandidate) {
    $root = $srcCandidate.FullName
}

# =========================
# FILE LIST
# =========================

$files = Get-ChildItem -Path $root -Recurse -File

if ($files.Count -eq 0) {
    $result.status = 'FAIL_POLICY'
    $result.reason_code = 'EMPTY_ZIP'
    $result.message = 'No files found in ZIP'
    Write-Report $result
    throw "EMPTY ZIP"
}

# =========================
# APPLY TO TARGET REPO
# =========================

foreach ($f in $files) {

    $rel = $f.FullName.Substring($root.Length).TrimStart("\","/")
    $targetPath = Join-Path $targetRepoPath $rel

    # FIX: безопасное получение директории (без Split-Path бага)
    $targetDir = [System.IO.Path]::GetDirectoryName($targetPath)

    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    Copy-Item $f.FullName $targetPath -Force
    $result.apply_changed = $true
}

# =========================
# DONE
# =========================

Write-Report $result

Write-Output "APPLY_DONE"
