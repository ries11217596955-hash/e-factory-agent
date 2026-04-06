param(
    [string]$ForceMode = ""
)

$ErrorActionPreference = 'Stop'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Write-FailArtifacts([string]$Message, [string]$ReportsDir, [string]$OutboxDir) {
    Ensure-Dir $ReportsDir
    Ensure-Dir $OutboxDir

    @"
STATUS:
FAIL

MODE:
REPO

ERROR:
$Message
"@ | Set-Content -LiteralPath (Join-Path $ReportsDir 'REPORT.txt') -Encoding UTF8

    Write-JsonFile -Path (Join-Path $ReportsDir 'audit_result.json') -Object ([pscustomobject]@{
        status = 'FAIL'
        mode = 'REPO'
        error = $Message
        checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    })

    "FAIL REPO`n$Message" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.fail') -Encoding UTF8
}

$Root = $PSScriptRoot
$Reports = Join-Path $Root 'reports'
$Outbox = Join-Path $Root 'outbox'
$Agent = Join-Path $Root 'agent.ps1'

Ensure-Dir $Reports
Ensure-Dir $Outbox

$mode = if (-not [string]::IsNullOrWhiteSpace($ForceMode)) {
    $ForceMode.ToUpperInvariant()
} elseif (-not [string]::IsNullOrWhiteSpace($env:FORCE_MODE)) {
    $env:FORCE_MODE.ToUpperInvariant()
} else {
    'REPO'
}

try {
    if ($mode -ne 'REPO') {
        throw "BASELINE LOCK: only REPO mode is allowed in this recovery pack. Requested mode: $mode"
    }

    $targetRepo = $env:TARGET_REPO_PATH
    if ([string]::IsNullOrWhiteSpace($targetRepo)) {
        $workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root '../../../../'))
        $targetRepo = Join-Path $workspaceRoot 'target_repo'
    }

    Write-Host "MODE: REPO"
    Write-Host "AUDIT ROOT: $targetRepo"

    if (-not (Test-Path -LiteralPath $targetRepo)) {
        throw "REPO NOT FOUND (checkout failed): $targetRepo"
    }

    & $Agent -Mode REPO -TargetPath $targetRepo
    if (-not $?) {
        throw 'agent.ps1 failed in REPO mode'
    }

    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-Error $msg
    Write-FailArtifacts -Message $msg -ReportsDir $Reports -OutboxDir $Outbox
    exit 1
}
