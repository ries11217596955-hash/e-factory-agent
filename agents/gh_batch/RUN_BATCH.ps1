# RUN_BATCH_FIXED_APPLY.ps1
# minimal working apply engine (clean version)

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

$files = Get-ChildItem -Path $temp -Recurse -File

if ($files.Count -eq 0) {
    $result.status = 'FAIL_POLICY'
    $result.reason_code = 'EMPTY_ZIP'
    $result.message = 'No files found in ZIP'
}

$repoRoot = $env:GITHUB_WORKSPACE

foreach ($f in $files) {
    $rel = $f.FullName.Substring($temp.Length).TrimStart("\/")
    $target = Join-Path $repoRoot $rel

    $dir = Split-Path $target
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    if (!(Test-Path $target) -or (Get-FileHash $f.FullName).Hash -ne (Get-FileHash $target -ErrorAction SilentlyContinue).Hash) {
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
