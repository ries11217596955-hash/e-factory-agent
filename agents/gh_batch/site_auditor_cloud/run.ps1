param()

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-FailureArtifacts {
    param(
        [string]$Root,
        [string]$Mode,
        [string]$Message,
        [string]$Detail = ""
    )

    $reports = Join-Path $Root "reports"
    $outbox  = Join-Path $Root "outbox"
    Ensure-Dir $reports
    Ensure-Dir $outbox

    $reportPath = Join-Path $reports "REPORT.txt"
    $lines = @(
        "STATUS:",
        "FAIL",
        "",
        "MODE:",
        $Mode,
        "",
        "ERROR:",
        $Message
    )
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $lines += ""
        $lines += "DETAIL:"
        $lines += $Detail
    }
    Set-Content -LiteralPath $reportPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

    $failJson = [pscustomobject]@{
        status = "FAIL"
        mode = $Mode
        error = $Message
        detail = $Detail
        timestamp_utc = [DateTime]::UtcNow.ToString("o")
    }
    $failJson | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports "audit_result.json") -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $outbox "DONE.fail") -Value $Message -Encoding UTF8
}

function Resolve-ExtractedRoot([string]$ExpandedPath) {
    $dirs = @(Get-ChildItem -LiteralPath $ExpandedPath -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 1) {
        return $dirs[0].FullName
    }
    return $ExpandedPath
}

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "input/inbox"
$Out   = Join-Path $Root "outbox"
$Reports = Join-Path $Root "reports"

Ensure-Dir $Out
Ensure-Dir $Reports

$ForceMode = [string]$env:FORCE_MODE
$Intake = Join-Path $Root "lib/intake_zip.ps1"

try {
    if ($ForceMode -eq "REPO") {
        $repoRoot = [string]$env:TARGET_REPO_PATH
        if ([string]::IsNullOrWhiteSpace($repoRoot)) {
            throw "TARGET_REPO_PATH is empty in REPO mode"
        }
        if (-not (Test-Path -LiteralPath $repoRoot)) {
            throw "TARGET_REPO_PATH not found: $repoRoot"
        }

        Write-Host "MODE: REPO (forced by workflow_dispatch)"
        Write-Host "AUDIT ROOT: $repoRoot"

        & "$Root/agent.ps1" -AuditMode REPO -TargetPath $repoRoot -BaseUrl $env:BASE_URL
        exit $LASTEXITCODE
    }

    if ($ForceMode -eq "ZIP") {
        if (!(Test-Path -LiteralPath $Inbox)) {
            throw "ZIP mode forced but inbox not found: $Inbox"
        }

        $zip = & $Intake -InboxPath $Inbox
        if ([string]::IsNullOrWhiteSpace($zip)) {
            throw "ZIP mode forced but no ZIP found in inbox"
        }

        $zip = "$zip".Trim()
        Write-Host "ZIP FOUND: $zip"
        Write-Host "MODE: ZIP"
        Write-Host "ZIP PATH: $zip"

        $Preflight = Join-Path $Root "lib/preflight.ps1"
        & $Preflight -ZipPath $zip
        Write-Host "PREFLIGHT OK"

        $tmp = Join-Path $Root "tmp_zip"
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $auditRoot = Resolve-ExtractedRoot $tmp

        Write-Host "AUDIT ROOT: $auditRoot"
        & "$Root/agent.ps1" -AuditMode ZIP -TargetPath $auditRoot
        exit $LASTEXITCODE
    }

    throw "Unsupported FORCE_MODE: '$ForceMode'"
}
catch {
    $msg = $_.Exception.Message
    Write-FailureArtifacts -Root $Root -Mode $ForceMode -Message $msg -Detail ($_ | Out-String)
    Write-Error $msg
    exit 1
}
