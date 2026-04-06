param()

$ErrorActionPreference = "Stop"

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$Root  = $PSScriptRoot
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# runtime folder:
#   agents/gh_batch/site_auditor_cloud
#
# inbox folder:
#   agents/site_auditor_cloud/input
#
# from runtime root we need to go up two levels to /agents
# then into /site_auditor_cloud/input

$AgentsRoot = Split-Path (Split-Path $Root -Parent) -Parent
$InboxDir   = Join-Path $AgentsRoot "site_auditor_cloud/input"
$RepoPath   = Join-Path $Root "target_repo"

$ZipFile = $null
if (Test-Path $InboxDir) {
    $ZipFile = Get-ChildItem -Path $InboxDir -Filter *.zip -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($null -ne $ZipFile) {
    $Mode = "ZIP"
} else {
    $Mode = "REPO"
}

Write-Output "MODE: $Mode"
Write-Output "ROOT: $Root"
Write-Output "INBOX: $InboxDir"

if ($Mode -eq "ZIP") {
    Write-Output "ZIP FILE: $($ZipFile.FullName)"

    $Extract = Join-Path $Root "zip_extract"
    if (Test-Path $Extract) {
        Remove-Item $Extract -Recurse -Force
    }

    Expand-Archive -Path $ZipFile.FullName -DestinationPath $Extract -Force

    $sub = Get-ChildItem -Path $Extract -Force

    if ($sub.Count -eq 1 -and $sub[0].PSIsContainer) {
        $Target = $sub[0].FullName
    } else {
        $Target = $Extract
    }
}
else {
    if (!(Test-Path $RepoPath)) {
        Write-Error "target_repo not found (REPO mode)"
        exit 1
    }

    $Target = $RepoPath
}

$Agent = Join-Path $Root "agent.ps1"
if (!(Test-Path $Agent)) {
    Write-Error "agent.ps1 not found: $Agent"
    exit 1
}

& powershell -NoProfile -ExecutionPolicy Bypass `
    -File $Agent `
    -TargetPath $Target `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "agent failed"
    exit 1
}

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok") -Encoding utf8

@"
RUN_ID: $RunId
STATUS: PASS
MODE: $Mode
TARGET: $Target
INBOX: $InboxDir
ZIP: $(if ($ZipFile) { $ZipFile.FullName } else { "NONE" })
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt") -Encoding utf8

Write-Output "DONE: $OutDir"
