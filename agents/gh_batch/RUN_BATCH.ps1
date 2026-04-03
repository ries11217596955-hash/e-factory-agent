# RUN_BATCH.ps1 — FIXED v3 (target checkout aware)

param(
    [string]$ZipPath,
    [string]$LogsDir
)

$ErrorActionPreference = 'Stop'

function Write-Report {
    param([hashtable]$result)

    if (-not (Test-Path -LiteralPath $LogsDir)) {
        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    }

    $reportPath = Join-Path $LogsDir ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$result = @{
    status                   = 'PASS'
    reason_code              = ''
    message                  = ''
    apply_changed            = $false

    expected_repo            = $env:EXPECTED_REPO
    effective_repo           = ''
    expected_branch          = $env:EXPECTED_BRANCH
    effective_branch         = ''

    target_repo_path         = $env:TARGET_REPO_PATH
    zip_path                 = $ZipPath
    logs_dir                 = $LogsDir
}

try {
    if (-not $env:TARGET_REPO_PATH) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'TARGET_REPO_PATH_MISSING'
        $result.message = 'TARGET_REPO_PATH is empty'
        Write-Report $result
        throw 'TARGET_REPO_PATH is empty'
    }

    $targetRepoPath = $env:TARGET_REPO_PATH

    if (-not (Test-Path -LiteralPath $targetRepoPath)) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'TARGET_REPO_PATH_INVALID'
        $result.message = "TARGET_REPO_PATH not found: $targetRepoPath"
        Write-Report $result
        throw "TARGET_REPO_PATH not found: $targetRepoPath"
    }

    $gitDir = Join-Path $targetRepoPath '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'TARGET_REPO_NOT_GIT'
        $result.message = "Target path is not a git checkout: $targetRepoPath"
        Write-Report $result
        throw "Target path is not a git checkout: $targetRepoPath"
    }

    Push-Location $targetRepoPath
    try {
        $effectiveRepo = ''
        $effectiveBranch = ''

        try {
            $remoteUrl = (git remote get-url origin 2>$null)
            if ($LASTEXITCODE -eq 0 -and $remoteUrl) {
                if ($remoteUrl -match 'github\.com[:/](.+?)(\.git)?$') {
                    $effectiveRepo = $matches[1]
                } else {
                    $effectiveRepo = $remoteUrl
                }
            }
        } catch {}

        try {
            $branchName = (git rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $branchName) {
                $effectiveBranch = $branchName.Trim()
            }
        } catch {}

        $result.effective_repo = $effectiveRepo
        $result.effective_branch = $effectiveBranch

        if ($env:EXPECTED_REPO -and $effectiveRepo -and ($effectiveRepo -ne $env:EXPECTED_REPO)) {
            $result.status = 'FAIL_POLICY'
            $result.reason_code = 'FAIL_WRONG_TARGET_REPO'
            $result.message = "Expected target repo '$($env:EXPECTED_REPO)' but got '$effectiveRepo'"
            Write-Report $result
            throw $result.message
        }

        if ($env:EXPECTED_BRANCH -and $effectiveBranch -and ($effectiveBranch -ne $env:EXPECTED_BRANCH)) {
            $result.status = 'FAIL_POLICY'
            $result.reason_code = 'FAIL_WRONG_TARGET_BRANCH'
            $result.message = "Expected target branch '$($env:EXPECTED_BRANCH)' but got '$effectiveBranch'"
            Write-Report $result
            throw $result.message
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'ZIP_NOT_FOUND'
        $result.message = "ZIP not found: $ZipPath"
        Write-Report $result
        throw "ZIP not found: $ZipPath"
    }

    $tempRoot = Join-Path $env:TEMP ("ghb_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempRoot -Force

        $payloadRoot = $tempRoot
        $items = Get-ChildItem -LiteralPath $tempRoot
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $payloadRoot = $items[0].FullName
        }

        $srcRoot = Join-Path $payloadRoot 'src'
        if (Test-Path -LiteralPath $srcRoot) {
            $payloadRoot = $srcRoot
        }

        $files = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File
        if (-not $files -or $files.Count -eq 0) {
            $result.status = 'FAIL_POLICY'
            $result.reason_code = 'EMPTY_ZIP'
            $result.message = 'No files found in ZIP payload'
            Write-Report $result
            throw 'No files found in ZIP payload'
        }

        foreach ($f in $files) {
            $rel = $f.FullName.Substring($payloadRoot.Length).TrimStart('\','/')

            if ([string]::IsNullOrWhiteSpace($rel)) {
                continue
            }

            $targetPath = Join-Path $targetRepoPath $rel
            $targetDir  = [System.IO.Path]::GetDirectoryName($targetPath)

            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }

            Copy-Item -LiteralPath $f.FullName -Destination $targetPath -Force
            $result.apply_changed = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Report $result
    Write-Output 'APPLY_DONE'
}
catch {
    if (-not $result.reason_code) {
        $result.status = 'FAIL_RUNTIME'
        $result.reason_code = 'RUN_BATCH_EXCEPTION'
        $result.message = $_.Exception.Message
        Write-Report $result
    }
    throw
}
