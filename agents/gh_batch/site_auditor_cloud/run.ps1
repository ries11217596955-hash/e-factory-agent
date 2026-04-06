param(
    [string]$ForceMode = "",
    [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Reset-Dir {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Route-Zip {
    param($src, $dstDir)

    if (-not (Test-Path $src)) { return $null }

    Ensure-Dir $dstDir

    $name = [IO.Path]::GetFileName($src)
    $dest = Join-Path $dstDir $name

    if (Test-Path $dest) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $base = [IO.Path]::GetFileNameWithoutExtension($name)
        $ext = [IO.Path]::GetExtension($name)
        $dest = Join-Path $dstDir "$base`_$stamp$ext"
    }

    Move-Item $src $dest -Force
    return $dest
}

# ---------------- PATHS ----------------

$ROOT = $PSScriptRoot

$INBOX = Join-Path $ROOT "input/inbox"
$PROCESSING = Join-Path $ROOT "input/processing"
$DONE = Join-Path $ROOT "input/done"
$FAILED = Join-Path $ROOT "input/failed"

$REPORTS = Join-Path $ROOT "reports"
$OUTBOX = Join-Path $ROOT "outbox"
$TMP = Join-Path $ROOT "tmp_zip"

Ensure-Dir $PROCESSING
Ensure-Dir $DONE
Ensure-Dir $FAILED
Ensure-Dir $REPORTS
Ensure-Dir $OUTBOX

# ---------------- MODE ----------------

$MODE = ""

if ($ForceMode) {
    $MODE = $ForceMode.ToUpper()
}
elseif ($env:FORCE_MODE) {
    $MODE = $env:FORCE_MODE.ToUpper()
}
else {
    $zip = Get-ChildItem $INBOX -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zip) { $MODE = "ZIP" } else { $MODE = "URL" }
}

Write-Host "MODE: $MODE"

# ---------------- REPO ----------------

if ($MODE -eq "REPO" -or $MODE -eq "UNIFIED") {

    $repo = $env:TARGET_REPO_PATH

    if (-not $repo) {
        $repo = Join-Path (Join-Path $ROOT "../../../../") "target_repo"
    }

    Write-Host "AUDIT ROOT: $repo"

    if (-not (Test-Path $repo)) {
        Write-Error "REPO NOT FOUND"
        exit 1
    }

    if ($MODE -eq "UNIFIED") {

        if (-not $BaseUrl) {
            if ($env:BASE_URL) {
                $BaseUrl = $env:BASE_URL
            } else {
                $BaseUrl = "https://automation-kb.pages.dev"
            }
        }

        Write-Host "BASE URL: $BaseUrl"

        & "$ROOT/agent.ps1" -Mode UNIFIED -TargetPath $repo -BaseUrl $BaseUrl
    }
    else {
        & "$ROOT/agent.ps1" -Mode REPO -TargetPath $repo
    }

    exit $LASTEXITCODE
}

# ---------------- ZIP ----------------

if ($MODE -eq "ZIP") {

    $zip = Get-ChildItem $INBOX -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $zip) {
        Write-Error "NO ZIP FOUND"
        exit 1
    }

    $zipPath = $zip.FullName
    Write-Host "ZIP FOUND: $zipPath"

    $procZip = Route-Zip $zipPath $PROCESSING

    Reset-Dir $TMP
    Expand-Archive $procZip -DestinationPath $TMP -Force

    $dir = Get-ChildItem $TMP -Directory | Select-Object -First 1

    if ($dir) {
        $root = $dir.FullName
    } else {
        $root = $TMP
    }

    Write-Host "AUDIT ROOT: $root"

    & "$ROOT/agent.ps1" -Mode ZIP -TargetPath $root

    if ($LASTEXITCODE -eq 0) {
        Route-Zip $procZip $DONE
        Write-Host "ZIP → DONE"
    }
    else {
        Route-Zip $procZip $FAILED
        Write-Host "ZIP → FAILED"
    }

    exit $LASTEXITCODE
}

# ---------------- URL ----------------

if ($MODE -eq "URL") {

    if (-not $BaseUrl) {
        if ($env:BASE_URL) {
            $BaseUrl = $env:BASE_URL
        } else {
            $BaseUrl = "https://automation-kb.pages.dev"
        }
    }

    Write-Host "BASE URL: $BaseUrl"

    & "$ROOT/agent.ps1" -Mode URL -BaseUrl $BaseUrl

    exit $LASTEXITCODE
}
