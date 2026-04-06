param()

$ErrorActionPreference = "Stop"

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$Root  = $PSScriptRoot
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$RepoPath = Join-Path $Root "target_repo"

if (!(Test-Path $RepoPath)) {
    Write-Error "target_repo not found"
    exit 1
}

$Agent = Join-Path $Root "agent.ps1"

if (!(Test-Path $Agent)) {
    Write-Error "agent.ps1 not found"
    exit 1
}

Write-Output "MODE: REPO"
Write-Output "TARGET: $RepoPath"

& $Agent `
    -TargetPath $RepoPath `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "agent failed"
    exit 1
}

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok") -Encoding utf8

@"
RUN_ID: $RunId
STATUS: PASS
MODE: REPO
TARGET: $RepoPath
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt") -Encoding utf8

Write-Output "DONE: $OutDir"
