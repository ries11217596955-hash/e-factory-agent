
param()

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "input/inbox"
$Out   = Join-Path $Root "outbox"

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$Intake = Join-Path $Root "lib/intake_zip.ps1"

if (!(Test-Path $Inbox)) {
    Write-Output "NO INBOX -> fallback to LIVE"
    & "$Root\agent.ps1"
    exit 0
}

$zip = & $Intake -InboxPath $Inbox

if (!$zip) {
    Write-Output "NO ZIP -> fallback LIVE"
    & "$Root\agent.ps1"
    exit 0
}

Write-Output "MODE: ZIP"

$Preflight = Join-Path $Root "lib/preflight.ps1"
& $Preflight -ZipPath $zip

$tmp = Join-Path $Root "tmp_zip"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip -DestinationPath $tmp -Force

& "$Root\agent.ps1" -TargetPath $tmp
