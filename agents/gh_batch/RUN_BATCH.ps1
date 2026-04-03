# RUN_BATCH_TARGET_LOCK_v3.ps1
# Applies ZIP payload into TARGET_REPO_PATH, preserves repo-relative paths,
# enforces src-only scope, and writes explicit target-binding fields to RUN_REPORT.

param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$LogsDir
)

$ErrorActionPreference = 'Stop'

function New-Result {
    return [ordered]@{
        status                  = 'PASS'
        reason_code             = ''
        message                 = ''
        fail_reason             = ''
        apply_changed           = $false
        expected_repo           = $env:EXPECTED_TARGET_REPO
        effective_repo          = $env:EFFECTIVE_TARGET_REPO
        expected_branch         = $env:EXPECTED_TARGET_BRANCH
        effective_branch        = $env:EFFECTIVE_TARGET_BRANCH
        source_repo             = $env:GITHUB_REPOSITORY
        source_ref              = $env:GITHUB_REF
        target_repo_root        = $env:TARGET_REPO_PATH
        zip_path                = $ZipPath
        applied_files           = @()
        skipped_identical_files = @()
        blocked_files           = @()
        extracted_root          = ''
        scanned_file_count      = 0
    }
}

function Write-RunReport {
    param(
        [Parameter(Mandatory)][hashtable]$Result,
        [Parameter(Mandatory)][string]$TargetLogsDir
    )

    if (-not (Test-Path -LiteralPath $TargetLogsDir)) {
        New-Item -ItemType Directory -Force -Path $TargetLogsDir | Out-Null
    }

    $reportPath = Join-Path $TargetLogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
    $Result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return $reportPath
}

function Normalize-RelPath {
    param([Parameter(Mandatory)][string]$PathText)

    $p = $PathText -replace '\\','/'
    while ($p.StartsWith('./')) {
        $p = $p.Substring(2)
    }
    return $p.TrimStart('/')
}

function Is-AllowedRelPath {
    param([Parameter(Mandatory)][string]$RelPath)

    if ([string]::IsNullOrWhiteSpace($RelPath)) { return $false }
    if ($RelPath.StartsWith('.git/')) { return $false }
    if ($RelPath.StartsWith('_site/')) { return $false }
    if ($RelPath.StartsWith('node_modules/')) { return $false }
    if ($RelPath.StartsWith('.github/')) { return $false }
    if ($RelPath -notmatch '^src/') { return $false }
    return $true
}

function Get-EffectivePayloadRoot {
    param([Parameter(Mandatory)][string]$ExtractRoot)

    $root = $ExtractRoot
    $items = @(Get-ChildItem -LiteralPath $ExtractRoot -Force)
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        $root = $items[0].FullName
    }
    return $root
}

$result = New-Result
$temp = Join-Path $env:TEMP ("ghb_" + [guid]::NewGuid().ToString())

try {
    New-Item -ItemType Directory -Force -Path $temp | Out-Null

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'ZIP_NOT_FOUND'
        $result.message = 'ZIP file not found'
        $result.fail_reason = $ZipPath
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH) -or -not (Test-Path -LiteralPath $env:TARGET_REPO_PATH)) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'TARGET_REPO_ROOT_MISSING'
        $result.message = 'TARGET_REPO_PATH is missing or does not exist'
        $result.fail_reason = [string]$env:TARGET_REPO_PATH
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    if ($env:EFFECTIVE_TARGET_REPO -ne $env:EXPECTED_TARGET_REPO) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'FAIL_WRONG_TARGET_REPO'
        $result.message = 'Effective target repo does not match expected target repo'
        $result.fail_reason = "expected=$($env:EXPECTED_TARGET_REPO); effective=$($env:EFFECTIVE_TARGET_REPO)"
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    if ($env:EFFECTIVE_TARGET_BRANCH -ne $env:EXPECTED_TARGET_BRANCH) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'FAIL_WRONG_TARGET_BRANCH'
        $result.message = 'Effective target branch does not match expected target branch'
        $result.fail_reason = "expected=$($env:EXPECTED_TARGET_BRANCH); effective=$($env:EFFECTIVE_TARGET_BRANCH)"
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $temp -Force

    $payloadRoot = Get-EffectivePayloadRoot -ExtractRoot $temp
    $result.extracted_root = $payloadRoot

    $files = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -Force -File | Sort-Object FullName)
    $result.scanned_file_count = $files.Count

    if ($files.Count -eq 0) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'EMPTY_ZIP'
        $result.message = 'No files found in ZIP'
        $result.fail_reason = 'Archive extracted successfully but contains no files'
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    $payloadRootFull = [System.IO.Path]::GetFullPath($payloadRoot)
    if (-not $payloadRootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $payloadRootFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $blocked = New-Object System.Collections.Generic.List[string]
    $applied = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]

    foreach ($file in $files) {
        $full = [System.IO.Path]::GetFullPath($file.FullName)
        $rel = Normalize-RelPath -PathText $full.Substring($payloadRootFull.Length)

        if (-not (Is-AllowedRelPath -RelPath $rel)) {
            $blocked.Add($rel) | Out-Null
            continue
        }

        $targetPath = Join-Path $env:TARGET_REPO_PATH ($rel -replace '/','\')
        $targetDir = Split-Path -LiteralPath $targetPath -Parent
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }

        $copyNeeded = $true
        if (Test-Path -LiteralPath $targetPath) {
            try {
                $h1 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                $h2 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
                if ($h1 -eq $h2) {
                    $copyNeeded = $false
                }
            }
            catch {
                $copyNeeded = $true
            }
        }

        if ($copyNeeded) {
            Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
            $applied.Add($rel) | Out-Null
            $result.apply_changed = $true
        }
        else {
            $skipped.Add($rel) | Out-Null
        }
    }

    $result.applied_files = @($applied)
    $result.skipped_identical_files = @($skipped)
    $result.blocked_files = @($blocked)

    if ($blocked.Count -gt 0 -and $applied.Count -eq 0) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'FAIL_SCOPE_NOT_ALLOWED'
        $result.message = 'ZIP contains files outside allowed src/ scope'
        $result.fail_reason = ($blocked -join '; ')
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    if ($blocked.Count -gt 0) {
        $result.status = 'FAIL_POLICY'
        $result.reason_code = 'FAIL_SCOPE_MIXED_CONTENT'
        $result.message = 'ZIP contains mixed allowed and forbidden files'
        $result.fail_reason = ($blocked -join '; ')
        Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
        exit 0
    }

    if (-not $result.apply_changed) {
        $result.reason_code = 'NO_EFFECT_OK'
        $result.message = 'No changes (idempotent)'
    }

    Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
    Write-Output "DONE"
}
catch {
    $result.status = 'FAIL_RUNTIME'
    $result.reason_code = 'UNHANDLED_EXCEPTION'
    $result.message = $_.Exception.Message
    $result.fail_reason = ($_ | Out-String).Trim()
    Write-RunReport -Result $result -TargetLogsDir $LogsDir | Out-Null
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
