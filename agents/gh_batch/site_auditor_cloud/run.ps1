# ===============================
# SITE_AUDITOR_AGENT v11 RUNNER
# ===============================

param(
    [string]$InputZip = "",
    [string]$TargetPath = "",
    [string]$WorkRoot = ".\work",
    [string]$OutRoot = ".\outbox"
)

$ErrorActionPreference = "Stop"

# ---------- paths ----------

$RunId = (Get-Date -Format "yyyyMMdd_HHmmss")
$RunDir = Join-Path $WorkRoot "run_$RunId"
$OutDir = Join-Path $OutRoot "run_$RunId"

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------- resolve target ----------

if ($InputZip -ne "") {
    if (!(Test-Path $InputZip)) {
        Write-Error "ZIP not found"
        exit 1
    }

    $ExtractDir = Join-Path $RunDir "input"
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

    Expand-Archive -Path $InputZip -DestinationPath $ExtractDir -Force

    # auto-root normalize (если ZIP с верхней папкой)
    $sub = Get-ChildItem $ExtractDir
    if ($sub.Count -eq 1 -and $sub[0].PSIsContainer) {
        $TargetPath = $sub[0].FullName
    } else {
        $TargetPath = $ExtractDir
    }
}

if ($TargetPath -eq "") {
    Write-Error "No input provided"
    exit 1
}

if (!(Test-Path $TargetPath)) {
    Write-Error "Target path not found"
    exit 1
}

# ---------- copy to run sandbox ----------

$Sandbox = Join-Path $RunDir "target"
Copy-Item $TargetPath $Sandbox -Recurse -Force

# ---------- run core ----------

$CoreScript = Join-Path $PSScriptRoot "agent.ps1"

if (!(Test-Path $CoreScript)) {
    Write-Error "agent.ps1 not found"
    exit 1
}

& powershell -NoProfile -ExecutionPolicy Bypass `
    -File $CoreScript `
    -TargetPath $Sandbox `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "Core failed"
    exit 1
}

# ---------- DONE markers ----------

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok")

# ---------- simple report ----------

$reportPath = Join-Path $OutDir "RUN_REPORT.txt"

@"
RUN_ID: $RunId
TARGET: $TargetPath
OUT_DIR: $OutDir
STATUS: PASS
TIME: $(Get-Date)
"@ | Out-File $reportPath -Encoding utf8

Write-Output "RUN COMPLETE: $OutDir"
