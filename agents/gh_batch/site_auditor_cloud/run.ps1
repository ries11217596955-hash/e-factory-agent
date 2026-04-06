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

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
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

    Write-JsonFile -Path (Join-Path $ReportsDir 'audit_result.json') -Object ([pscustomobject]@{
        status = 'FAIL'
        mode = $Mode
        error = $Message
        checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    })

    "FAIL $Mode`n$Message" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.fail') -Encoding UTF8
}

function Get-SiteRootFromExpandedZip([string]$ExpandedRoot) {
    if (Test-Path -LiteralPath (Join-Path $ExpandedRoot 'src')) {
        return $ExpandedRoot
    }

    $dirs = Get-ChildItem -LiteralPath $ExpandedRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'src')) {
            return $dir.FullName
        }
    }

    throw "Expanded ZIP does not contain repo root with src/: $ExpandedRoot"
}

function Get-LatestZip([string]$InboxPath) {
    if (-not (Test-Path -LiteralPath $InboxPath)) { return $null }
    $zip = Get-ChildItem -LiteralPath $InboxPath -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $zip) { return $null }
    return $zip.FullName
}

function Move-Zip([string]$SourcePath, [string]$DestinationDir) {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) { return $null }
    if (-not (Test-Path -LiteralPath $SourcePath)) { return $null }
    Ensure-Dir $DestinationDir
    $dest = Join-Path $DestinationDir ([System.IO.Path]::GetFileName($SourcePath))
    if (Test-Path -LiteralPath $dest) {
        $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $ext  = [System.IO.Path]::GetExtension($SourcePath)
        $dest = Join-Path $DestinationDir ("{0}_{1}{2}" -f $leaf, $stamp, $ext)
    }
    Move-Item -LiteralPath $SourcePath -Destination $dest -Force
    return $dest
}

$Root = $PSScriptRoot
$Inbox = Join-Path $Root 'input/inbox'
$Processing = Join-Path $Root 'input/processing'
$Done = Join-Path $Root 'input/done'
$Failed = Join-Path $Root 'input/failed'
$Reports = Join-Path $Root 'reports'
$Outbox = Join-Path $Root 'outbox'
$TmpZip = Join-Path $Root 'tmp_zip'
$Agent = Join-Path $Root 'agent.ps1'

Ensure-Dir $Reports
Ensure-Dir $Outbox
Ensure-Dir $Inbox
Ensure-Dir $Processing
Ensure-Dir $Done
Ensure-Dir $Failed

$mode = if (-not [string]::IsNullOrWhiteSpace($ForceMode)) {
    $ForceMode.ToUpperInvariant()
} elseif (-not [string]::IsNullOrWhiteSpace($env:FORCE_MODE)) {
    $env:FORCE_MODE.ToUpperInvariant()
} else {
    'REPO'
}

$zipInProcess = $null

try {
    switch ($mode) {
        'REPO' {
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
            if (-not $?) { throw 'agent.ps1 failed in REPO mode' }
        }

        'ZIP' {
            $zip = Get-LatestZip -InboxPath $Inbox
            if ([string]::IsNullOrWhiteSpace($zip)) {
                throw "ZIP mode requested but no ZIP found in inbox: $Inbox"
            }

            Write-Host "MODE: ZIP"
            Write-Host "ZIP FOUND: $zip"

            $zipInProcess = Move-Zip -SourcePath $zip -DestinationDir $Processing
            if ([string]::IsNullOrWhiteSpace($zipInProcess)) {
                throw 'Failed to move ZIP from inbox to processing'
            }

            Reset-Dir $TmpZip
            Expand-Archive -LiteralPath $zipInProcess -DestinationPath $TmpZip -Force
            $auditRoot = Get-SiteRootFromExpandedZip -ExpandedRoot $TmpZip
            Write-Host "AUDIT ROOT: $auditRoot"

            & $Agent -Mode ZIP -TargetPath $auditRoot
            if (-not $?) { throw 'agent.ps1 failed in ZIP mode' }

            $null = Move-Zip -SourcePath $zipInProcess -DestinationDir $Done
        }

        'URL' {
            $effectiveBaseUrl = if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
                $BaseUrl
            } elseif (-not [string]::IsNullOrWhiteSpace($env:BASE_URL)) {
                $env:BASE_URL
            } else {
                'https://automation-kb.pages.dev'
            }

            Write-Host "MODE: URL"
            Write-Host "BASE URL: $effectiveBaseUrl"

            & $Agent -Mode URL -BaseUrl $effectiveBaseUrl
            if (-not $?) { throw 'agent.ps1 failed in URL mode' }
        }

        default {
            throw "Unsupported mode: $mode"
        }
    }

    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-Error $msg

    if ($mode -eq 'ZIP' -and -not [string]::IsNullOrWhiteSpace($zipInProcess) -and (Test-Path -LiteralPath $zipInProcess)) {
        $null = Move-Zip -SourcePath $zipInProcess -DestinationDir $Failed
    }

    Write-FailArtifacts -Mode $mode -Message $msg -ReportsDir $Reports -OutboxDir $Outbox
    exit 1
}
