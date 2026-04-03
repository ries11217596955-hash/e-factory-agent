# RUN_BATCH.ps1
# FIXED v5
# - truthful target commit closure
# - full-repo ZIP restore support
# - payload ZIP support (src-only)
# - PowerShell 5.1 compatible
# - empty git output safe

param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [string]$LogsDir
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------

function Ensure-Dir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [AllowEmptyString()]
        [string]$Content = ''
    )

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Dir -Path $dir
    }

    if ($null -eq $Content) {
        $Content = ''
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Object
    )

    $json = $Object | ConvertTo-Json -Depth 20
    Write-Utf8File -Path $Path -Content $json
}

function Exec-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    Push-Location $RepoPath
    try {
        $output = & git @Args 2>&1
        $exitCode = $LASTEXITCODE

        $joined = ''
        if ($null -ne $output) {
            if ($output -is [System.Array]) {
                $joined = ($output -join [Environment]::NewLine)
            }
            else {
                $joined = [string]$output
            }
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = $joined
        }
    }
    finally {
        Pop-Location
    }
}

function Save-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )

    $r = Exec-Git -Args $Args -RepoPath $RepoPath

    $safeOutput = ''
    if ($null -ne $r.Output) {
        $safeOutput = [string]$r.Output
    }

    Write-Utf8File -Path $OutPath -Content $safeOutput
    return $r
}

function Get-GitHeadSha {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $r = Exec-Git -Args @('rev-parse', 'HEAD') -RepoPath $RepoPath
    if ($r.ExitCode -ne 0) { return '' }
    return ($r.Output.Trim())
}

function Get-GitBranchName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $r = Exec-Git -Args @('rev-parse', '--abbrev-ref', 'HEAD') -RepoPath $RepoPath
    if ($r.ExitCode -ne 0) { return '' }
    return ($r.Output.Trim())
}

function Get-GitRemoteUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $r = Exec-Git -Args @('remote', 'get-url', 'origin') -RepoPath $RepoPath
    if ($r.ExitCode -ne 0) { return '' }
    return ($r.Output.Trim())
}

function Normalize-GitHubRepoFromUrl {
    param(
        [string]$RemoteUrl
    )

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return '' }

    $u = $RemoteUrl.Trim()

    if ($u -match 'github\.com[:/](.+?)(\.git)?$') {
        return $matches[1]
    }

    return $u
}

function Is-FullRepoZipRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $signals = @(
        '.gitignore',
        '.eleventy.js',
        'package.json',
        'package-lock.json',
        'src',
        '.github'
    )

    foreach ($s in $signals) {
        if (Test-Path -LiteralPath (Join-Path $RootPath $s)) {
            return $true
        }
    }

    return $false
}

function Get-PayloadMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UnpackedRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRepoPath
    )

    $candidateRoot = $UnpackedRoot
    $items = Get-ChildItem -LiteralPath $UnpackedRoot -Force

    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        $candidateRoot = $items[0].FullName
    }

    if (Is-FullRepoZipRoot -RootPath $candidateRoot) {
        return [pscustomobject]@{
            Mode          = 'FULL_REPO'
            EffectiveRoot = $candidateRoot
            CopyBase      = $candidateRoot
            TargetBase    = $TargetRepoPath
        }
    }

    $srcDirect = Join-Path $candidateRoot 'src'
    if (Test-Path -LiteralPath $srcDirect) {
        return [pscustomobject]@{
            Mode          = 'SRC_ONLY'
            EffectiveRoot = $candidateRoot
            CopyBase      = $srcDirect
            TargetBase    = (Join-Path $TargetRepoPath 'src')
        }
    }

    return [pscustomobject]@{
        Mode          = 'GENERIC_ROOT'
        EffectiveRoot = $candidateRoot
        CopyBase      = $candidateRoot
        TargetBase    = $TargetRepoPath
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $base = $BasePath.TrimEnd('\','/')
    $full = $FullPath

    if ($full.Length -lt $base.Length) {
        return ''
    }

    $rel = $full.Substring($base.Length).TrimStart('\','/')
    return $rel
}

function Write-RunReport {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report,
        [Parameter(Mandatory = $true)]
        [string]$LogsDirPath
    )

    Ensure-Dir -Path $LogsDirPath
    $reportPath = Join-Path $LogsDirPath ("RUN_REPORT_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
    Write-JsonFile -Path $reportPath -Object $Report
    return $reportPath
}

# ------------------------------------------------------------
# init paths
# ------------------------------------------------------------

Ensure-Dir -Path $LogsDir

$RunRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = (Get-Location).Path
}

$ArtifactsRoot = Join-Path $LogsDir 'artifacts'
$MetaDir       = Join-Path $ArtifactsRoot 'meta'
$GitDir        = Join-Path $ArtifactsRoot 'git'
Ensure-Dir -Path $ArtifactsRoot
Ensure-Dir -Path $MetaDir
Ensure-Dir -Path $GitDir

# ------------------------------------------------------------
# init report
# ------------------------------------------------------------

$report = @{
    status                   = 'INIT'
    reason_code              = ''
    message                  = ''
    zip_path                 = $ZipPath
    logs_dir                 = $LogsDir

    expected_target_repo     = $env:EXPECTED_REPO
    effective_target_repo    = ''
    expected_target_branch   = $env:EXPECTED_BRANCH
    effective_target_branch  = ''

    target_repo_path         = $env:TARGET_REPO_PATH
    target_pre_head          = ''
    target_post_head         = ''

    payload_mode             = ''
    payload_root             = ''
    copy_base                = ''
    target_base              = ''

    files_discovered         = 0
    files_copied             = 0
    apply_changed            = $false

    target_commit_created    = $false
    target_push_result       = ''
    target_commit_sha        = ''
}

# ------------------------------------------------------------
# main
# ------------------------------------------------------------

$tempRoot = ''

try {
    # -------------------------
    # preflight
    # -------------------------
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        throw "ZIP_NOT_FOUND: $ZipPath"
    }

    if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH)) {
        throw 'TARGET_REPO_PATH_MISSING'
    }

    $targetRepoPath = $env:TARGET_REPO_PATH

    if (-not (Test-Path -LiteralPath $targetRepoPath)) {
        throw "TARGET_REPO_PATH_INVALID: $targetRepoPath"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $targetRepoPath '.git'))) {
        throw "TARGET_REPO_NOT_GIT: $targetRepoPath"
    }

    $effectiveRepo   = Normalize-GitHubRepoFromUrl -RemoteUrl (Get-GitRemoteUrl -RepoPath $targetRepoPath)
    $effectiveBranch = Get-GitBranchName -RepoPath $targetRepoPath
    $preHead         = Get-GitHeadSha -RepoPath $targetRepoPath

    $report.effective_target_repo   = $effectiveRepo
    $report.effective_target_branch = $effectiveBranch
    $report.target_pre_head         = $preHead

    Write-JsonFile -Path (Join-Path $MetaDir 'TARGET_BINDING.json') -Object @{
        expected_target_repo    = $env:EXPECTED_REPO
        effective_target_repo   = $effectiveRepo
        expected_target_branch  = $env:EXPECTED_BRANCH
        effective_target_branch = $effectiveBranch
        target_repo_path        = $targetRepoPath
        pre_head                = $preHead
    }

    Save-GitOutput -RepoPath $targetRepoPath -Args @('status', '--porcelain=v1') -OutPath (Join-Path $GitDir 'TARGET_STATUS_AT_START.txt') | Out-Null
    Save-GitOutput -RepoPath $targetRepoPath -Args @('log', '--oneline', '-n', '10') -OutPath (Join-Path $GitDir 'TARGET_HEAD_LOG_AT_START.txt') | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($env:EXPECTED_REPO)) {
        if ($effectiveRepo -ne $env:EXPECTED_REPO) {
            $report.status = 'FAIL_POLICY'
            $report.reason_code = 'FAIL_WRONG_TARGET_REPO'
            $report.message = "Expected repo '$($env:EXPECTED_REPO)' but got '$effectiveRepo'"
            throw $report.message
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:EXPECTED_BRANCH)) {
        if ($effectiveBranch -ne $env:EXPECTED_BRANCH) {
            $report.status = 'FAIL_POLICY'
            $report.reason_code = 'FAIL_WRONG_TARGET_BRANCH'
            $report.message = "Expected branch '$($env:EXPECTED_BRANCH)' but got '$effectiveBranch'"
            throw $report.message
        }
    }

    # -------------------------
    # unpack
    # -------------------------
    $tempRoot = Join-Path $env:TEMP ('ghb_' + [guid]::NewGuid().ToString('N'))
    Ensure-Dir -Path $tempRoot

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempRoot -Force

    $modeInfo = Get-PayloadMode -UnpackedRoot $tempRoot -TargetRepoPath $targetRepoPath
    $copyBase   = $modeInfo.CopyBase
    $targetBase = $modeInfo.TargetBase

    $report.payload_mode = $modeInfo.Mode
    $report.payload_root = $modeInfo.EffectiveRoot
    $report.copy_base    = $copyBase
    $report.target_base  = $targetBase

    Write-JsonFile -Path (Join-Path $MetaDir 'PAYLOAD_MODE.json') -Object @{
        mode           = $modeInfo.Mode
        effective_root = $modeInfo.EffectiveRoot
        copy_base      = $copyBase
        target_base    = $targetBase
    }

    if (-not (Test-Path -LiteralPath $copyBase)) {
        throw "COPY_BASE_NOT_FOUND: $copyBase"
    }

    Ensure-Dir -Path $targetBase

    $files = Get-ChildItem -LiteralPath $copyBase -Recurse -File
    $report.files_discovered = @($files).Count

    if ($report.files_discovered -eq 0) {
        $report.status = 'FAIL_POLICY'
        $report.reason_code = 'EMPTY_ZIP'
        $report.message = 'No files found in ZIP payload'
        throw $report.message
    }

    # -------------------------
    # copy files
    # -------------------------
    $copyLog = New-Object System.Collections.Generic.List[string]

    foreach ($f in $files) {
        $rel = Get-RelativePath -BasePath $copyBase -FullPath $f.FullName
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }

        $dest = Join-Path $targetBase $rel
        $destDir = [System.IO.Path]::GetDirectoryName($dest)
        Ensure-Dir -Path $destDir

        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $report.files_copied++
        $copyLog.Add(($rel + ' -> ' + $dest))
    }

    Write-Utf8File -Path (Join-Path $MetaDir 'COPIED_FILES.txt') -Content ($copyLog -join [Environment]::NewLine)

    # -------------------------
    # git evidence before staging
    # -------------------------
    Save-GitOutput -RepoPath $targetRepoPath -Args @('status', '--porcelain=v1') -OutPath (Join-Path $GitDir 'TARGET_STATUS_BEFORE_STAGE.txt') | Out-Null
    Save-GitOutput -RepoPath $targetRepoPath -Args @('diff', '--name-status', '--cached') -OutPath (Join-Path $GitDir 'TARGET_CACHED_DIFF_BEFORE_STAGE.txt') | Out-Null
    Save-GitOutput -RepoPath $targetRepoPath -Args @('diff', '--name-status') -OutPath (Join-Path $GitDir 'TARGET_WORKTREE_DIFF_BEFORE_STAGE.txt') | Out-Null

    # -------------------------
    # stage all target changes
    # -------------------------
    $addResult = Exec-Git -Args @('add', '-A') -RepoPath $targetRepoPath
    Write-Utf8File -Path (Join-Path $GitDir 'TARGET_GIT_ADD_OUTPUT.txt') -Content $addResult.Output

    if ($addResult.ExitCode -ne 0) {
        throw ('GIT_ADD_FAILED: ' + $addResult.Output)
    }

    Save-GitOutput -RepoPath $targetRepoPath -Args @('status', '--porcelain=v1') -OutPath (Join-Path $GitDir 'TARGET_STATUS_AFTER_STAGE.txt') | Out-Null
    $cachedDiff = Save-GitOutput -RepoPath $targetRepoPath -Args @('diff', '--name-status', '--cached') -OutPath (Join-Path $GitDir 'TARGET_CACHED_DIFF_NAME_STATUS.txt')

    $cachedText = ''
    if ($null -ne $cachedDiff.Output) {
        $cachedText = [string]$cachedDiff.Output
    }

    $hasStagedDiff = (-not [string]::IsNullOrWhiteSpace($cachedText.Trim()))

    if (-not $hasStagedDiff) {
        $report.apply_changed = $false
        $report.target_commit_created = $false
        $report.target_push_result = 'NO_COMMIT'
        $report.target_commit_sha = ''
        $report.target_post_head = $preHead
        $report.status = 'FAIL_RUNTIME'
        $report.reason_code = 'NO_TARGET_COMMIT'
        $report.message = 'No staged diff after apply; target commit not created'

        Write-JsonFile -Path (Join-Path $MetaDir 'TARGET_COMMIT_SUMMARY.json') -Object @{
            commit_created = $false
            push_result    = 'NO_COMMIT'
            commit_sha     = ''
            pre_head       = $preHead
            post_head      = $preHead
            reason_code    = 'NO_TARGET_COMMIT'
            message        = 'No staged diff after apply; target commit not created'
        }

        throw $report.message
    }

    $report.apply_changed = $true

    # -------------------------
    # commit
    # -------------------------
    $commitMessage = 'gh-batch apply to automation-kb'
    $commitResult = Exec-Git -Args @('-c', 'user.name=gh-batch-bot', '-c', 'user.email=gh-batch-bot@users.noreply.github.com', 'commit', '-m', $commitMessage) -RepoPath $targetRepoPath
    Write-Utf8File -Path (Join-Path $GitDir 'TARGET_GIT_COMMIT_OUTPUT.txt') -Content $commitResult.Output

    if ($commitResult.ExitCode -ne 0) {
        throw ('GIT_COMMIT_FAILED: ' + $commitResult.Output)
    }

    $postCommitHead = Get-GitHeadSha -RepoPath $targetRepoPath
    $report.target_post_head = $postCommitHead

    if ([string]::IsNullOrWhiteSpace($postCommitHead) -or ($postCommitHead -eq $preHead)) {
        $report.status = 'FAIL_RUNTIME'
        $report.reason_code = 'NO_NEW_TARGET_SHA'
        $report.message = 'Commit command ran but target HEAD did not advance'

        Write-JsonFile -Path (Join-Path $MetaDir 'TARGET_COMMIT_SUMMARY.json') -Object @{
            commit_created = $false
            push_result    = 'NO_COMMIT'
            commit_sha     = ''
            pre_head       = $preHead
            post_head      = $postCommitHead
            reason_code    = 'NO_NEW_TARGET_SHA'
            message        = 'Commit command ran but target HEAD did not advance'
        }

        throw $report.message
    }

    # -------------------------
    # push
    # -------------------------
    $pushResult = Exec-Git -Args @('push', 'origin', $effectiveBranch) -RepoPath $targetRepoPath
    Write-Utf8File -Path (Join-Path $GitDir 'TARGET_GIT_PUSH_OUTPUT.txt') -Content $pushResult.Output

    if ($pushResult.ExitCode -ne 0) {
        $report.status = 'FAIL_RUNTIME'
        $report.reason_code = 'TARGET_PUSH_FAILED'
        $report.message = 'Target push failed: ' + $pushResult.Output

        Write-JsonFile -Path (Join-Path $MetaDir 'TARGET_COMMIT_SUMMARY.json') -Object @{
            commit_created = $false
            push_result    = 'PUSH_FAIL'
            commit_sha     = $postCommitHead
            pre_head       = $preHead
            post_head      = $postCommitHead
            reason_code    = 'TARGET_PUSH_FAILED'
            message        = $pushResult.Output
        }

        throw $report.message
    }

    $report.target_commit_created = $true
    $report.target_push_result = 'PUSH_OK'
    $report.target_commit_sha = $postCommitHead
    $report.status = 'PASS'
    $report.reason_code = ''
    $report.message = 'Target repo updated successfully'

    Save-GitOutput -RepoPath $targetRepoPath -Args @('log', '--oneline', '-n', '10') -OutPath (Join-Path $GitDir 'TARGET_HEAD_LOG_STAT.txt') | Out-Null

    Write-JsonFile -Path (Join-Path $MetaDir 'TARGET_COMMIT_SUMMARY.json') -Object @{
        commit_created = $true
        push_result    = 'PUSH_OK'
        commit_sha     = $postCommitHead
        pre_head       = $preHead
        post_head      = $postCommitHead
        reason_code    = ''
        message        = 'Target repo updated successfully'
    }
}
catch {
    if ([string]::IsNullOrWhiteSpace($report.status) -or $report.status -eq 'INIT') {
        $report.status = 'FAIL_RUNTIME'
    }

    if ([string]::IsNullOrWhiteSpace($report.reason_code)) {
        $msg = $_.Exception.Message
        if ($msg -match '^([A-Z0-9_]+):') {
            $report.reason_code = $matches[1]
        }
        else {
            $report.reason_code = 'RUN_BATCH_EXCEPTION'
        }
    }

    if ([string]::IsNullOrWhiteSpace($report.message)) {
        $report.message = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($report.target_post_head)) {
        if (-not [string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH) -and (Test-Path -LiteralPath $env:TARGET_REPO_PATH)) {
            $report.target_post_head = Get-GitHeadSha -RepoPath $env:TARGET_REPO_PATH
        }
    }

    Write-JsonFile -Path (Join-Path $MetaDir 'FAIL_CONTEXT.json') -Object @{
        status      = $report.status
        reason_code = $report.reason_code
        message     = $report.message
        zip_path    = $ZipPath
    }

    throw
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH) -and (Test-Path -LiteralPath $env:TARGET_REPO_PATH)) {
        Save-GitOutput -RepoPath $env:TARGET_REPO_PATH -Args @('status', '--porcelain=v1') -OutPath (Join-Path $GitDir 'TARGET_STATUS_FINAL.txt') | Out-Null
    }

    $null = Write-RunReport -Report $report -LogsDirPath $LogsDir

    if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
