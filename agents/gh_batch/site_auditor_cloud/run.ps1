param()

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "input/inbox"
$Out   = Join-Path $Root "outbox"

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ForceMode = $env:FORCE_MODE
$Intake = Join-Path $Root "lib/intake_zip.ps1"

if ($ForceMode -eq "REPO") {
    Write-Host "MODE: REPO (forced by workflow_dispatch)"
    & "$Root\agent.ps1"
    exit $LASTEXITCODE
}

if ($ForceMode -eq "ZIP") {
    if (!(Test-Path $Inbox)) {
        Write-Error "ZIP mode forced but inbox not found: $Inbox"
        exit 1
    }

    $zip = & $Intake -InboxPath $Inbox

    if ([string]::IsNullOrWhiteSpace($zip)) {
        Write-Error "ZIP mode forced but no ZIP found in inbox"
        exit 1
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
}

# fallback safety
if (Test-Path $Inbox) {
    $zip = & $Intake -InboxPath $Inbox
    if (-not [string]::IsNullOrWhiteSpace($zip)) {
        $zip = "$zip".Trim()
        Write-Host "MODE: ZIP (fallback)"
        Write-Host "ZIP PATH: $zip"

        $Preflight = Join-Path $Root "lib/preflight.ps1"
        & $Preflight -ZipPath $zip

        $tmp = Join-Path $Root "tmp_zip"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        & "$Root\agent.ps1" -TargetPath $tmp
        exit $LASTEXITCODE
    }
}

Write-Host "MODE: LIVE/REPO (fallback)"
& "$Root\agent.ps1"
exit $LASTEXITCODE
