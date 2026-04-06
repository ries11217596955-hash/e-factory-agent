\
param(
    [string]$ForceMode = "",
    [string]$BaseUrl = ""
)

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

function Get-UniqueDestinationPath([string]$Dir, [string]$LeafName) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($LeafName)
    $ext = [System.IO.Path]::GetExtension($LeafName)
    $candidate = Join-Path $Dir $LeafName
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    $suffix = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $candidate = Join-Path $Dir ("{0}_{1}{2}" -f $baseName, $suffix, $ext)
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    $i = 1
    while ($true) {
        $candidate = Join-Path $Dir ("{0}_{1}_{2}{3}" -f $baseName, $suffix, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

function Route-ZipFile([string]$SourcePath, [string]$DestinationDir) {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) { return $null }
    if (-not (Test-Path -LiteralPath $SourcePath)) { return $null }
    Ensure-Dir $DestinationDir
    $dest = Get-UniqueDestinationPath -Dir $DestinationDir -LeafName ([System.IO.Path]::GetFileName($SourcePath))
    Move-Item -LiteralPath $SourcePath -Destination $dest -Force
    return $dest
}

$Root = $PSScriptRoot
$Inbox = Join-Path $Root 'input/inbox'
$Processing = Join-Path $Root 'input/processing'
$Done = Join-Path $Root 'input/done'
$Failed = Join-Path $Root 'input/failed'
$Outbox = Join-Path $Root 'outbox'
$Reports = Join-Path $Root 'reports'
$TmpZip = Join-Path $Root 'tmp_zip'
$Intake = Join-Path $Root 'lib/intake_zip.ps1'
$Preflight = Join-Path $Root 'lib/preflight.ps1'
$Agent = Join-Path $Root 'agent.ps1'

Ensure-Dir $Outbox
Ensure-Dir $Reports
Ensure-Dir $Processing
Ensure-Dir $Done
Ensure-Dir $Failed

$mode = if ([string]::IsNullOrWhiteSpace($env:FORCE_MODE)) { 'URL' } else { $env:FORCE_MODE.ToUpperInvariant() }
$zipInProcess = $null

try {
    if ($mode -eq 'REPO' -or $mode -eq 'UNIFIED') {
        $targetRepo = $env:TARGET_REPO_PATH
        if ([string]::IsNullOrWhiteSpace($targetRepo)) {
            $workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root '../../../../'))
            $targetRepo = Join-Path $workspaceRoot 'target_repo'
        }
        Write-Host ("MODE: {0}" -f $mode)
        Write-Host "AUDIT ROOT: $targetRepo"
        if (-not (Test-Path -LiteralPath $targetRepo)) {
            throw "REPO NOT FOUND (checkout failed): $targetRepo"
        }
        $global:LASTEXITCODE = 0
        if ($mode -eq 'UNIFIED') {
            $baseUrl = if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { 'https://automation-kb.pages.dev' } else { $env:BASE_URL }
            Write-Host "BASE URL: $baseUrl"
            & $Agent -Mode UNIFIED -TargetPath $targetRepo -BaseUrl $baseUrl
            if (-not $?) { throw 'agent.ps1 failed in UNIFIED mode' }
        } else {
            & $Agent -Mode REPO -TargetPath $targetRepo
            if (-not $?) { throw 'agent.ps1 failed in REPO mode' }
        }
        exit 0
    }

    if ($mode -eq 'ZIP') {
        if (-not (Test-Path -LiteralPath $Inbox)) { throw "ZIP mode forced but inbox not found: $Inbox" }
        $zip = & $Intake -InboxPath $Inbox
        if ([string]::IsNullOrWhiteSpace($zip)) { throw 'ZIP mode forced but no ZIP found in inbox' }
        $zip = "$zip".Trim()
        Write-Host "MODE: ZIP"
        Write-Host "ZIP FOUND: $zip"

        $zipInProcess = Route-ZipFile -SourcePath $zip -DestinationDir $Processing
        if ([string]::IsNullOrWhiteSpace($zipInProcess)) { throw 'Failed to move ZIP from inbox to processing' }

        Write-Host "ZIP PATH: $zipInProcess"
        & $Preflight -ZipPath $zipInProcess
        Write-Host 'PREFLIGHT OK'

        Reset-Dir $TmpZip
        Expand-Archive -LiteralPath $zipInProcess -DestinationPath $TmpZip -Force
        $auditRoot = Get-SiteRootFromExpandedZip -ExpandedRoot $TmpZip
        Write-Host "AUDIT ROOT: $auditRoot"

        $global:LASTEXITCODE = 0
        & $Agent -Mode ZIP -TargetPath $auditRoot
        if ($?) {
            $routed = Route-ZipFile -SourcePath $zipInProcess -DestinationDir $Done
            if ($null -ne $routed) { Write-Host "ZIP ROUTED: DONE -> $routed" }
            exit 0
        }

        $routed = Route-ZipFile -SourcePath $zipInProcess -DestinationDir $Failed
        if ($null -ne $routed) { Write-Host "ZIP ROUTED: FAILED -> $routed" }
        throw 'agent.ps1 failed in ZIP mode'
    }

    $baseUrl = if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { 'https://automation-kb.pages.dev' } else { $env:BASE_URL }
    Write-Host "MODE: URL"
    Write-Host "BASE URL: $baseUrl"
    $global:LASTEXITCODE = 0
    & $Agent -Mode URL -BaseUrl $baseUrl
    if (-not $?) { throw 'agent.ps1 failed in URL mode' }
    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-Error $msg
    if ($mode -eq 'ZIP' -and -not [string]::IsNullOrWhiteSpace($zipInProcess) -and (Test-Path -LiteralPath $zipInProcess)) {
        $routed = Route-ZipFile -SourcePath $zipInProcess -DestinationDir $Failed
        if ($null -ne $routed) { Write-Host "ZIP ROUTED: FAILED -> $routed" }
    }
    Write-FailArtifacts -Mode $mode -Message $msg -ReportsDir $Reports -OutboxDir $Outbox
    exit 1
}
