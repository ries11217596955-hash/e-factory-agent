param()

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "input/inbox"
$Out   = Join-Path $Root "outbox"

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$Intake = Join-Path $Root "lib/intake_zip.ps1"

if (!(Test-Path $Inbox)) {
    Write-Host "NO INBOX -> fallback to LIVE"
    & "$Root\agent.ps1"
    exit 0
}

$zip = & $Intake -InboxPath $Inbox

if ([string]::IsNullOrWhiteSpace($zip)) {
    Write-Host "NO ZIP -> fallback LIVE"
    & "$Root\agent.ps1"
    exit 0
}

$zip = "$zip".Trim()

Write-Host "MODE: ZIP"
Write-Host "ZIP PATH: $zip"

$Preflight = Join-Path $Root "lib/preflight.ps1"
& $Preflight -ZipPath $zip

$tmp = Join-Path $Root "tmp_zip"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath $tmp -Force

& "$Root\agent.ps1" -TargetPath $tmp
exit $LASTEXITCODE
