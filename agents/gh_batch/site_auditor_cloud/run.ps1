param()

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Reset-Dir([string]$Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-FailArtifacts([string]$Mode, [string]$Message, [string]$ReportsDir, [string]$OutboxDir) {
    Ensure-Dir $ReportsDir
    Ensure-Dir $OutboxDir
    @"
STATUS:
FAIL

MODE:
$Mode

ERROR:
$Message
"@ | Set-Content -LiteralPath (Join-Path $ReportsDir 'REPORT.txt') -Encoding UTF8

    @{ status='FAIL'; mode=$Mode; error=$Message; checked_at_utc=(Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $ReportsDir 'audit_result.json') -Encoding UTF8

    "FAIL $Mode`n$Message" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.fail') -Encoding UTF8
}

function Get-SiteRootFromExpandedZip([string]$ExpandedRoot) {
    $dirs = Get-ChildItem -LiteralPath $ExpandedRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'src')) { return $dir.FullName }
    }
    if (Test-Path -LiteralPath (Join-Path $ExpandedRoot 'src')) { return $ExpandedRoot }
    throw "Expanded ZIP does not contain repo root with src/: $ExpandedRoot"
}

$Root = $PSScriptRoot
$Inbox = Join-Path $Root 'input/inbox'
$Outbox = Join-Path $Root 'outbox'
$Reports = Join-Path $Root 'reports'
$TmpZip = Join-Path $Root 'tmp_zip'
$Intake = Join-Path $Root 'lib/intake_zip.ps1'
$Preflight = Join-Path $Root 'lib/preflight.ps1'
$Agent = Join-Path $Root 'agent.ps1'

Ensure-Dir $Outbox
Ensure-Dir $Reports

$mode = if ([string]::IsNullOrWhiteSpace($env:FORCE_MODE)) { 'URL' } else { $env:FORCE_MODE.ToUpperInvariant() }

try {
    if ($mode -eq 'REPO') {
        $targetRepo = $env:TARGET_REPO_PATH
        if ([string]::IsNullOrWhiteSpace($targetRepo)) {
            $targetRepo = Join-Path (Split-Path -Parent (Split-Path -Parent $Root)) 'target_repo'
        }
        Write-Host "MODE: REPO (forced by workflow_dispatch)"
        Write-Host "AUDIT ROOT: $targetRepo"
        & $Agent -Mode REPO -TargetPath $targetRepo
        exit $LASTEXITCODE
    }

    if ($mode -eq 'ZIP') {
        if (-not (Test-Path -LiteralPath $Inbox)) { throw "ZIP mode forced but inbox not found: $Inbox" }
        $zip = & $Intake -InboxPath $Inbox
        if ([string]::IsNullOrWhiteSpace($zip)) { throw 'ZIP mode forced but no ZIP found in inbox' }
        $zip = "$zip".Trim()
        Write-Host "MODE: ZIP"
        Write-Host "ZIP PATH: $zip"
        & $Preflight -ZipPath $zip
        Reset-Dir $TmpZip
        Expand-Archive -LiteralPath $zip -DestinationPath $TmpZip -Force
        $auditRoot = Get-SiteRootFromExpandedZip -ExpandedRoot $TmpZip
        Write-Host "AUDIT ROOT: $auditRoot"
        & $Agent -Mode ZIP -TargetPath $auditRoot
        exit $LASTEXITCODE
    }

    $baseUrl = if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { 'https://automation-kb.pages.dev' } else { $env:BASE_URL }
    Write-Host "MODE: URL"
    Write-Host "BASE URL: $baseUrl"
    & $Agent -Mode URL -BaseUrl $baseUrl
    exit $LASTEXITCODE
}
catch {
    $msg = $_.Exception.Message
    Write-Error $msg
    Write-FailArtifacts -Mode $mode -Message $msg -ReportsDir $Reports -OutboxDir $Outbox
    exit 1
}
