param()

$ErrorActionPreference = "Stop"

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$Root  = $PSScriptRoot
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$AgentsRoot = Split-Path (Split-Path $Root -Parent) -Parent
$InboxDir   = Join-Path $AgentsRoot "site_auditor_cloud/input"
$RepoPath   = Join-Path $Root "target_repo"

$ZipFile = $null
if (Test-Path $InboxDir) {
    $ZipFile = Get-ChildItem $InboxDir -Filter *.zip -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($ZipFile) {
    $Mode = "ZIP"
} else {
    $Mode = "REPO"
}

Write-Output "MODE: $Mode"

if ($Mode -eq "ZIP") {

    Write-Output "ZIP: $($ZipFile.FullName)"

    $Extract = Join-Path $Root "zip_extract"

    if (Test-Path $Extract) {
        Remove-Item $Extract -Recurse -Force
    }

    Expand-Archive -Path $ZipFile.FullName -DestinationPath $Extract -Force

    $sub = Get-ChildItem $Extract

    if ($sub.Count -eq 1 -and $sub[0].PSIsContainer) {
        $Target = $sub[0].FullName
    } else {
        $Target = $Extract
    }

} else {

    if (!(Test-Path $RepoPath)) {
        Write-Error "target_repo not found"
        exit 1
    }

    $Target = $RepoPath
}

$Agent = Join-Path $Root "agent.ps1"

if (!(Test-Path $Agent)) {
    Write-Error "agent.ps1 not found"
    exit 1
}

# ===== ВАЖНЫЙ ФИКС =====
# Никакого powershell, просто вызываем скрипт

& $Agent `
    -TargetPath $Target `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "agent failed"
    exit 1
}

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok")

@"
RUN_ID: $RunId
STATUS: PASS
MODE: $Mode
TARGET: $Target
ZIP: $(if ($ZipFile) {$ZipFile.FullName} else {"NONE"})
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt")

Write-Output "DONE: $OutDir"
