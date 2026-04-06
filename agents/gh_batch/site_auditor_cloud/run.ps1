param()

$ErrorActionPreference = "Stop"

$RunId = (Get-Date -Format "yyyyMMdd_HHmmss")
$Root = $PSScriptRoot
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ===== CRITICAL FIX =====
# Ищем ZIP НЕ только локально, а по workspace

$ZipFile = Get-ChildItem -Path $Root -Recurse -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -First 1

# repo path (как создаёт workflow)
$RepoPath = Join-Path $Root "target_repo"

# ===== MODE =====

if ($ZipFile) {
    $Mode = "ZIP"
} else {
    $Mode = "REPO"
}

Write-Output "MODE: $Mode"

# ===== TARGET =====

if ($Mode -eq "ZIP") {

    Write-Output "ZIP FOUND: $($ZipFile.FullName)"

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

# ===== RUN AGENT =====

$Agent = Join-Path $Root "agent.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass `
    -File $Agent `
    -TargetPath $Target `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "agent failed"
    exit 1
}

# ===== DONE =====

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok")

@"
RUN_ID: $RunId
STATUS: PASS
MODE: $Mode
TARGET: $Target
ZIP: $(if ($ZipFile) {$ZipFile.FullName} else {"NONE"})
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt")

Write-Output "DONE: $OutDir"
