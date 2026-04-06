param()

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Start)
    $cursor = (Resolve-Path $Start).Path
    while ($true) {
        if (Test-Path (Join-Path $cursor ".git")) { return $cursor }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $Start
}

function Expand-ZipToAuditRoot {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )

    if (Test-Path $DestinationRoot) {
        Remove-Item $DestinationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $DestinationRoot -Force

    $dirs = @(Get-ChildItem -LiteralPath $DestinationRoot -Directory -Force | Where-Object { $_.Name -notin @('__MACOSX') })
    $files = @(Get-ChildItem -LiteralPath $DestinationRoot -File -Force)

    if ($files.Count -eq 0 -and $dirs.Count -eq 1) {
        return $dirs[0].FullName
    }

    return $DestinationRoot
}

$Root = $PSScriptRoot
$RepoRoot = Resolve-RepoRoot -Start $Root
$Inbox = Join-Path $Root "input/inbox"
$Out   = Join-Path $Root "outbox"
$Reports = Join-Path $Root "reports"

New-Item -ItemType Directory -Force -Path $Out | Out-Null
New-Item -ItemType Directory -Force -Path $Reports | Out-Null

$ForceMode = [string]$env:FORCE_MODE
$Intake = Join-Path $Root "lib/intake_zip.ps1"
$TargetRepo = [string]$env:TARGET_REPO_PATH
$BaseUrl = [string]$env:SITE_AUDITOR_BASE_URL

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = "https://automation-kb.pages.dev"
}

if ($ForceMode -eq "REPO") {
    Write-Host "MODE: REPO (forced by workflow_dispatch)"

    if ([string]::IsNullOrWhiteSpace($TargetRepo)) {
        $candidate = Join-Path $RepoRoot "target_repo"
        if (Test-Path $candidate) {
            $TargetRepo = $candidate
        }
        else {
            $TargetRepo = $RepoRoot
        }
    }

    Write-Host "TARGET PATH: $TargetRepo"
    & "$Root\agent.ps1" -Mode "REPO" -TargetPath $TargetRepo -BaseUrl $BaseUrl
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
    $auditRoot = Expand-ZipToAuditRoot -ZipPath $zip -DestinationRoot $tmp

    Write-Host "AUDIT ROOT: $auditRoot"
    & "$Root\agent.ps1" -Mode "ZIP" -TargetPath $auditRoot -ZipPath $zip
    exit $LASTEXITCODE
}

# fallback
if (Test-Path $Inbox) {
    $zip = & $Intake -InboxPath $Inbox
    if (-not [string]::IsNullOrWhiteSpace($zip)) {
        $zip = "$zip".Trim()
        $tmp = Join-Path $Root "tmp_zip"
        $auditRoot = Expand-ZipToAuditRoot -ZipPath $zip -DestinationRoot $tmp
        Write-Host "MODE: ZIP (fallback)"
        Write-Host "ZIP PATH: $zip"
        Write-Host "AUDIT ROOT: $auditRoot"
        & "$Root\agent.ps1" -Mode "ZIP" -TargetPath $auditRoot -ZipPath $zip
        exit $LASTEXITCODE
    }
}

Write-Host "MODE: REPO (fallback)"
$fallbackTarget = if (Test-Path (Join-Path $RepoRoot "target_repo")) { Join-Path $RepoRoot "target_repo" } else { $RepoRoot }
Write-Host "TARGET PATH: $fallbackTarget"
& "$Root\agent.ps1" -Mode "REPO" -TargetPath $fallbackTarget -BaseUrl $BaseUrl
exit $LASTEXITCODE
