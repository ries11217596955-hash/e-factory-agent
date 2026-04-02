# RUN_BATCH_FINAL_v2.ps1
# FINAL VERSION — stable apply + robust root detection

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
}

$temp = Join-Path $env:TEMP ("ghb_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
    Expand-Archive -Path $ZipPath -DestinationPath $temp -Force
} catch {
    $result.status = 'FAIL_RUNTIME'
    $result.reason_code = 'ZIP_EXTRACT_FAIL'
    $result.message = $_.Exception.Message
}

# --- ROOT DETECTION (FINAL FIX) ---

$root = $temp

# unwrap single wrapper folder
$items = Get-ChildItem $temp
if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
    $root = $items[0].FullName
}

# FORCE detect src anywhere inside
$srcCandidate = Get-ChildItem -Path $root -Recurse -Directory | Where-Object { $_.Name -eq 'src' } | Select-Object -First 1

if ($srcCandidate) {
    $root = $srcCandidate.FullName
}

# ----------------------------------

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

    $copyNeeded = $true
    if (Test-Path $target) {
        try {
            $h1 = (Get-FileHash $f.FullName).Hash
            $h2 = (Get-FileHash $target).Hash
            if ($h1 -eq $h2) { $copyNeeded = $false }
        } catch {}
    }

    if ($copyNeeded) {
        Copy-Item $f.FullName $target -Force
        $result.apply_changed = $true
    }
}

if (-not $result.apply_changed -and $result.status -eq 'PASS') {
    $result.reason_code = 'NO_EFFECT_OK'
    $result.message = 'No changes (idempotent)'
}

$reportPath = Join-Path $LogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
$result | ConvertTo-Json -Depth 5 | Set-Content $reportPath

Write-Output "DONE"
