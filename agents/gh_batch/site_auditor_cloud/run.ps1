param()

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "input/inbox"
$Outbox = Join-Path $Root "outbox"
$Reports = Join-Path $Root "reports"
$Intake = Join-Path $Root "lib/intake_zip.ps1"
$Preflight = Join-Path $Root "lib/preflight.ps1"
$ForceMode = [string]$env:FORCE_MODE
$BaseUrl = [string]$env:BASE_URL
$TargetRepo = [string]$env:TARGET_REPO

New-Item -ItemType Directory -Force -Path $Outbox,$Reports | Out-Null

function Resolve-RepoRoot {
    param([string]$BasePath)
    if ([string]::IsNullOrWhiteSpace($BasePath)) { return $null }
    if (-not (Test-Path -LiteralPath $BasePath)) { return $null }

    $items = @(Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        $child = $items[0].FullName
        if (Test-Path -LiteralPath (Join-Path $child 'src')) { return $child }
        return $child
    }
    return $BasePath
}

function Invoke-Capture {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    Write-Host "CAPTURE BASE URL: $Url"
    $env:BASE_URL = $Url
    node ./capture.mjs
}

function Finalize-Run {
    param([string]$Status, [string]$Mode)

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $report = Join-Path $Reports 'REPORT.txt'
    $doneFile = if ($Status -eq 'OK') { Join-Path $Reports 'DONE.ok' } else { Join-Path $Reports 'DONE.fail' }
    Set-Content -LiteralPath $doneFile -Encoding UTF8 -Value @(
        "status=$Status"
        "mode=$Mode"
        "timestamp=$stamp"
    )

    $summary = [pscustomobject]@{
        status = $Status
        mode = $Mode
        timestamp = $stamp
        report_exists = (Test-Path -LiteralPath $report)
        reports_path = $Reports
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Reports 'audit_result.json') -Encoding UTF8

    $zipPath = Join-Path $Outbox ("site_audit_{0}_{1}.zip" -f $Mode.ToLower(), $stamp)
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $Reports '*') -DestinationPath $zipPath -Force
    Write-Host "OUTBOX ZIP: $zipPath"
}

try {
    if ($ForceMode -eq 'REPO') {
        Write-Host 'MODE: REPO'
        if ([string]::IsNullOrWhiteSpace($TargetRepo) -or -not (Test-Path -LiteralPath $TargetRepo)) {
            throw "TARGET_REPO not found: $TargetRepo"
        }
        $repoRoot = Resolve-RepoRoot -BasePath $TargetRepo
        Write-Host "AUDIT ROOT: $repoRoot"
        Invoke-Capture -Url $BaseUrl
        & "$Root/agent.ps1" -Mode 'REPO' -TargetPath $repoRoot -BaseUrl $BaseUrl
        if ($LASTEXITCODE -ne 0) { throw "agent.ps1 failed in REPO mode" }
        Finalize-Run -Status 'OK' -Mode 'REPO'
        exit 0
    }

    $zip = $null
    if (Test-Path -LiteralPath $Inbox) {
        $zip = & $Intake -InboxPath $Inbox
    }

    if ($ForceMode -eq 'ZIP' -or -not [string]::IsNullOrWhiteSpace($zip)) {
        if ([string]::IsNullOrWhiteSpace($zip)) {
            throw 'ZIP mode requested but no ZIP found in inbox'
        }
        $zip = ([string]$zip).Trim()
        Write-Host 'MODE: ZIP'
        Write-Host "ZIP PATH: $zip"
        & $Preflight -ZipPath $zip
        $tmp = Join-Path $Root 'tmp_zip'
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $repoRoot = Resolve-RepoRoot -BasePath $tmp
        Write-Host "AUDIT ROOT: $repoRoot"
        & "$Root/agent.ps1" -Mode 'ZIP' -TargetPath $repoRoot -BaseUrl ''
        if ($LASTEXITCODE -ne 0) { throw "agent.ps1 failed in ZIP mode" }
        Finalize-Run -Status 'OK' -Mode 'ZIP'
        exit 0
    }

    throw 'No valid mode resolved. Manual uses REPO; push to inbox uses ZIP.'
}
catch {
    $msg = $_.Exception.Message
    Write-Error $msg
    Set-Content -LiteralPath (Join-Path $Reports 'DONE.fail') -Encoding UTF8 -Value $msg
    Finalize-Run -Status 'FAIL' -Mode $(if([string]::IsNullOrWhiteSpace($ForceMode)){'UNKNOWN'}else{$ForceMode})
    exit 1
}
