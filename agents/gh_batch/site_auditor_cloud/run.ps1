param()

$ErrorActionPreference = "Stop"

$RunId = (Get-Date -Format "yyyyMMdd_HHmmss")
$Root = "$PSScriptRoot"
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ВАЖНО: target_repo уже создаётся workflow checkout
$Target = Join-Path $Root "target_repo"

if (!(Test-Path $Target)) {
    Write-Error "target_repo not found"
    exit 1
}

$Agent = Join-Path $Root "agent.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass `
    -File $Agent `
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
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt")

Write-Output "DONE: $OutDir"
