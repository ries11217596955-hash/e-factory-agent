[CmdletBinding()]
param(
    [string]$InboxDir = '',
    [string]$DoneDir  = '',
    [string]$LogsDir  = '',
    [string]$TempRoot = '',
    [string]$RepoOwner = 'ries11217596955-hash',
    [string]$RepoName  = 'automation-kb',
    [string]$Branch    = 'main',
    [int]$MaxFiles = 500,
    [int]$MaxTotalMB = 100,
    [switch]$RememberToken = $true,
    [switch]$ForgetToken,
    [switch]$WhatIfOnly,
    [switch]$NoAutoFix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ScriptRoot {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }
    if ($MyInvocation -and $MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Parent $PSCommandPath)
    }
    return (Get-Location).Path
}

function New-Dir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-UsableTempRoot {
    param([string]$PreferredPath)
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) { $candidates += $PreferredPath }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) { $candidates += (Join-Path $env:TEMP 'GH_BATCH_TMP') }
    if (-not [string]::IsNullOrWhiteSpace($env:TMP))  { $candidates += (Join-Path $env:TMP  'GH_BATCH_TMP') }
    try { $candidates += (Join-Path ([System.IO.Path]::GetTempPath()) 'GH_BATCH_TMP') } catch {}
    $candidates += (Join-Path (Resolve-ScriptRoot) 'temp')
    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            New-Dir -Path $candidate
            $probe = Join-Path $candidate ('write_probe_{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $candidate
        }
        catch {}
    }
    throw 'Could not find a writable temp root.'
}

$script:BatchRoot = Resolve-ScriptRoot
if ([string]::IsNullOrWhiteSpace($InboxDir)) { $InboxDir = Join-Path $script:BatchRoot 'inbox' }
if ([string]::IsNullOrWhiteSpace($DoneDir))  { $DoneDir  = Join-Path $script:BatchRoot 'done' }
if ([string]::IsNullOrWhiteSpace($LogsDir))  { $LogsDir  = Join-Path $script:BatchRoot 'logs' }
$TempRoot = Get-UsableTempRoot -PreferredPath $TempRoot

New-Dir -Path $InboxDir
New-Dir -Path $DoneDir
New-Dir -Path $LogsDir
New-Dir -Path $TempRoot

$script:StateDir = Join-Path $script:BatchRoot '.state'
New-Dir -Path $script:StateDir
$script:LockFile = Join-Path $script:StateDir 'RUN_BATCH.lock'
$script:ProcessedFile = Join-Path $script:StateDir 'processed_sha256.txt'
$script:LogFile = Join-Path $LogsDir ('RUN_BATCH_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:FallbackLogFile = Join-Path $script:BatchRoot 'RUN_BATCH_fallback.log'
$script:BatchExpandDir = Join-Path $TempRoot ('BATCH_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:JsonReportPath = Join-Path $LogsDir ('RUN_REPORT_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$script:FinalStatus = 'FAIL'
$script:FailReason = ''
$script:ZipName = ''
$script:ZipSha256 = ''
$script:BatchFileCount = 0
$script:BatchSizeMB = 0
$script:PreviewADD = 0
$script:PreviewUPD = 0
$script:PreviewSKIP = 0
$script:AcceptedFileCount = 0
$script:RejectedFileCount = 0
$script:RejectedPathSample = ''
$script:PolicyMode = 'WEBOPS_PARTIAL_ACCEPT_SAFEFIX'
$script:BaseCommitSha = ''
$script:BaseTreeSha = ''
$script:NewTreeSha = ''
$script:NewCommitSha = ''
$script:GitHubToken = $null
$script:Config = $null
$script:AutoFixRecords = @()
$script:RejectRecords = @()
$script:AcceptedPaths = @()

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
    catch {
        try { Add-Content -LiteralPath $script:FallbackLogFile -Value $line -Encoding UTF8 } catch {}
    }
}

function Write-StartupError {
    param([Parameter(Mandatory)][string]$Message)
    $path = Join-Path $script:BatchRoot ('STARTUP_ERROR_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Set-Content -LiteralPath $path -Value $Message -Encoding UTF8
}

function Get-TokenStorePath {
    $rootBase = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($rootBase) -or -not (Test-Path -LiteralPath $rootBase)) {
        $rootBase = $script:BatchRoot
    }
    $root = Join-Path $rootBase '.gh_batch'
    New-Dir -Path $root
    return (Join-Path $root 'github_pat.xml')
}

function Write-JsonReport {
    $payload = [ordered]@{
        status          = $script:FinalStatus
        fail_reason     = $script:FailReason
        repo            = "$RepoOwner/$RepoName"
        branch          = $Branch
        zip             = $script:ZipName
        zip_sha256      = $script:ZipSha256
        files           = $script:BatchFileCount
        size_mb         = $script:BatchSizeMB
        preview_add     = $script:PreviewADD
        preview_upd     = $script:PreviewUPD
        preview_skip    = $script:PreviewSKIP
        accepted        = $script:AcceptedFileCount
        rejected        = $script:RejectedFileCount
        rejected_sample = $script:RejectedPathSample
        policy_mode     = $script:PolicyMode
        base_commit     = $script:BaseCommitSha
        base_tree       = $script:BaseTreeSha
        new_tree        = $script:NewTreeSha
        new_commit      = $script:NewCommitSha
        log_file        = $script:LogFile
        json_report     = $script:JsonReportPath
        autofix         = @($script:AutoFixRecords)
        rejects         = @($script:RejectRecords)
        accepted_paths  = @($script:AcceptedPaths)
        timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $script:JsonReportPath -Value $json -Encoding UTF8
}

function Write-DeployReport {
    $reportPath = Join-Path $LogsDir ('DEPLOY_REPORT_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines = @(
        "Status      : $script:FinalStatus",
        "FailReason  : $script:FailReason",
        "Repo        : $RepoOwner/$RepoName",
        "Branch      : $Branch",
        "ZIP         : $script:ZipName",
        "ZIP_SHA256  : $script:ZipSha256",
        "Files       : $script:BatchFileCount",
        "SizeMB      : $script:BatchSizeMB",
        "PreviewADD  : $script:PreviewADD",
        "PreviewUPD  : $script:PreviewUPD",
        "PreviewSKIP : $script:PreviewSKIP",
        "Accepted    : $script:AcceptedFileCount",
        "Rejected    : $script:RejectedFileCount",
        "RejectSample: $script:RejectedPathSample",
        "PolicyMode  : $script:PolicyMode",
        "BaseCommit  : $script:BaseCommitSha",
        "BaseTree    : $script:BaseTreeSha",
        "NewTree     : $script:NewTreeSha",
        "NewCommit   : $script:NewCommitSha",
        "LogFile     : $script:LogFile",
        "JsonReport  : $script:JsonReportPath",
        "Timestamp   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )
    Set-Content -LiteralPath $reportPath -Value $lines -Encoding UTF8
    Write-JsonReport
    Write-Host "Report: $reportPath"
}

function Fail-Run {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [int]$ExitCode = 1
    )
    $script:FinalStatus = 'FAIL'
    $script:FailReason = $Reason
    Write-Log -Level ERROR -Message $Reason
    Write-DeployReport
    exit $ExitCode
}

function Acquire-Lock {
    if (Test-Path -LiteralPath $script:LockFile) {
        $existing = Get-Content -LiteralPath $script:LockFile -ErrorAction SilentlyContinue
        throw "Another RUN_BATCH instance appears active. Lock file: $script:LockFile $existing"
    }
    Set-Content -LiteralPath $script:LockFile -Value @(
        "PID=$PID",
        "Started=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Host=$env:COMPUTERNAME"
    ) -Encoding UTF8
}

function Release-Lock {
    if (Test-Path -LiteralPath $script:LockFile) {
        Remove-Item -LiteralPath $script:LockFile -Force -ErrorAction SilentlyContinue
    }
}

function Save-Token {
    param([Parameter(Mandatory)][string]$Token)
    $path = Get-TokenStorePath
    $secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
    $secure | Export-Clixml -Path $path
    Write-Log 'Token saved to user-scoped secure store.'
}

function Load-StoredToken {
    $path = Get-TokenStorePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $secure = Import-Clixml -Path $path
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }
    catch {
        Write-Log -Level WARN -Message "Stored token exists but could not be read: $($_.Exception.Message)"
        return $null
    }
}

function Remove-StoredToken {
    $path = Get-TokenStorePath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Log 'Stored token removed.'
    }
    else {
        Write-Log 'No stored token found.' -Level WARN
    }
}

function Read-TokenInteractive {
    $secure = Read-Host 'Enter GitHub PAT' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-GitHubToken {
    if ($ForgetToken) {
        Remove-StoredToken
        exit 0
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GH_BATCH_PAT)) {
        Write-Log 'Using token from env: GH_BATCH_PAT'
        return $env:GH_BATCH_PAT
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
        Write-Log 'Using token from env: GITHUB_PAT'
        return $env:GITHUB_PAT
    }
    $stored = Load-StoredToken
    if ($stored) {
        Write-Log 'Using stored token from user-scoped secure store.'
        return $stored
    }
    $token = Read-TokenInteractive
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Empty token received.'
    }
    if ($RememberToken) {
        Save-Token -Token $token
    }
    return $token
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [object]$Body
    )
    $headers = @{
        Authorization = "Bearer $script:GitHubToken"
        Accept        = 'application/vnd.github+json'
        'User-Agent'  = 'GH_BATCH_POWERSHELL'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $params = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    return (Invoke-RestMethod @params)
}

function Get-Sha1Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        return (($sha1.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha1.Dispose()
    }
}

function Get-Sha256HexForFile {
    param([Parameter(Mandatory)][string]$Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return (($sha256.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Test-AlreadyProcessedZip {
    param([Parameter(Mandatory)][string]$Sha256)
    if (-not (Test-Path -LiteralPath $script:ProcessedFile)) { return $false }
    $lines = Get-Content -LiteralPath $script:ProcessedFile -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -eq $Sha256) { return $true }
    }
    return $false
}

function Mark-ProcessedZip {
    param([Parameter(Mandatory)][string]$Sha256)
    Add-Content -LiteralPath $script:ProcessedFile -Value $Sha256 -Encoding UTF8
}

function Get-BatchZip {
    $zips = @(Get-ChildItem -LiteralPath $InboxDir -File -Filter '*.zip' | Sort-Object LastWriteTime)
    Write-Log "Inbox path: $InboxDir"
    Write-Log "ZIP count detected: $($zips.Count)"
    if ($zips.Count -eq 0) { throw "No ZIP files found in inbox: $InboxDir" }
    if ($zips.Count -gt 1) { Write-Log -Level WARN -Message "Multiple ZIP files found. Using oldest: $($zips[0].Name)" }
    Write-Log "Selected ZIP: $($zips[0].FullName)"
    return $zips[0]
}

function Expand-BatchZip {
    param([Parameter(Mandatory)][string]$ZipPath)
    if (Test-Path -LiteralPath $script:BatchExpandDir) {
        Remove-Item -LiteralPath $script:BatchExpandDir -Recurse -Force
    }
    New-Dir -Path $script:BatchExpandDir
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $script:BatchExpandDir -Force
    Write-Log "ZIP expanded: $ZipPath"
}

function Get-AutoRoot {
    param([Parameter(Mandatory)][string]$ExpandedRoot)
    $files = @(Get-ChildItem -LiteralPath $ExpandedRoot -File -Recurse -Force)
    if ($files.Count -eq 0) { throw 'Expanded ZIP is empty.' }
    $topItems = @(Get-ChildItem -LiteralPath $ExpandedRoot -Force)
    if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
        $folderName = $topItems[0].Name.ToLowerInvariant()
        if ($folderName -eq 'src') {
            Write-Log "SRC root detected: keeping 'src/' as patch root"
            return $ExpandedRoot
        }
        Write-Log "Auto-root detected: stripping top folder '$($topItems[0].Name)'"
        return $topItems[0].FullName
    }
    return $ExpandedRoot
}

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )
    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $fileFull = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull = $baseFull + [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $fileFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "File outside expanded root: $fileFull"
    }
    $relative = $fileFull.Substring($baseFull.Length)
    $relative = $relative -replace '\\','/'
    $relative = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($relative)) { throw "Resolved empty relative path for '$FullPath'" }
    if ($relative.StartsWith('/')) { $relative = $relative.TrimStart('/') }
    if ($relative -match '^[A-Za-z]:') { throw "Absolute drive path not allowed: $relative" }
    if ($relative.StartsWith('../') -or $relative -eq '..' -or $relative -like '*/../*') {
        throw "Path traversal not allowed: $relative"
    }
    return $relative
}

function Test-IsBatchMetaFile {
    param([Parameter(Mandatory)][string]$RelativePath)
    $name = [System.IO.Path]::GetFileName($RelativePath)
    $patterns = @('README*', 'SHA256*', 'MANIFEST*', 'SMOKE*', 'PATCH_NOTES*', 'DELETE_LIST*')
    foreach ($pattern in $patterns) {
        if ($name -like $pattern) { return $true }
    }
    return $false
}

function Load-AgentConfig {
    $path = Join-Path $script:BatchRoot 'agent.config.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        throw "Config parse failed: $path :: $($_.Exception.Message)"
    }
}

function Get-ConfigArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Test-WebOpsPathPolicy {
    param([Parameter(Mandatory)][string]$RelativePath)
    $allowedPrefixes = @('src/','assets/','public/','static/','docs/','data/','.github/')
    $allowedExact = @('package.json','package-lock.json','.eleventy.js','eleventy.config.js','README.md')
    if ($script:Config -and $script:Config.allowed_scope) {
        $allowedPrefixes = @()
        $allowedExact = @()
        foreach ($entry in (Get-ConfigArray -Value $script:Config.allowed_scope)) {
            $s = [string]$entry
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            if ($s.EndsWith('/')) { $allowedPrefixes += $s } else { $allowedExact += $s }
        }
    }
    if ($allowedExact -contains $RelativePath) { return $true }
    foreach ($prefix in $allowedPrefixes) {
        if ($RelativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-ForbiddenPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $parts = $RelativePath -split '/'
    $forbidden = @('_site','node_modules','.git','.cache','dist','coverage','tmp','temp')
    if ($script:Config -and $script:Config.forbidden_paths) {
        $forbidden = Get-ConfigArray -Value $script:Config.forbidden_paths
    }
    foreach ($part in $parts) {
        foreach ($bad in $forbidden) {
            if ($part.Equals([string]$bad, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Get-TextExtensions {
    $list = @('.md','.html','.njk','.json','.js','.css','.xml','.txt','.yml','.yaml','.svg','.csv','.11tydata.js')
    if ($script:Config -and $script:Config.text_extensions) {
        $list = Get-ConfigArray -Value $script:Config.text_extensions
    }
    return @($list | ForEach-Object { [string]$_ })
}

function Test-IsTextPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $ext = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($RelativePath).ToLowerInvariant()
    foreach ($candidate in (Get-TextExtensions)) {
        $c = ([string]$candidate).ToLowerInvariant()
        if ($name.EndsWith($c) -or $ext -eq $c) { return $true }
    }
    return $false
}

function Get-FileInventory {
    param([Parameter(Mandatory)][string]$SourceRoot)
    $items = @()
    $dup = @{}
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force)
    foreach ($file in $files) {
        $relativePath = Normalize-RelativePath -BasePath $SourceRoot -FullPath $file.FullName
        if (Test-IsBatchMetaFile -RelativePath $relativePath) {
            Write-Log -Level WARN -Message "Skipping batch meta file: $relativePath"
            continue
        }
        $key = $relativePath.ToLowerInvariant()
        if ($dup.ContainsKey($key)) { throw "Duplicate path after normalization: $relativePath" }
        $dup[$key] = $true
        $items += [pscustomobject]@{
            RelativePath = $relativePath
            FullPath     = $file.FullName
            Length       = [int64]$file.Length
        }
    }
    return @($items)
}

function Get-TextReadResult {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 0 -and ($bytes | Where-Object { $_ -eq 0 } | Select-Object -First 1)) {
        return [pscustomobject]@{ Success = $false; Reason = 'NUL_BYTE'; Text = $null; Encoding = 'binary' }
    }
    try {
        $enc = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $enc.GetString($bytes)
        return [pscustomobject]@{ Success = $true; Reason = ''; Text = $text; Encoding = 'utf8' }
    }
    catch {
        try {
            $text = [System.Text.Encoding]::Default.GetString($bytes)
            return [pscustomobject]@{ Success = $true; Reason = ''; Text = $text; Encoding = 'default' }
        }
        catch {
            return [pscustomobject]@{ Success = $false; Reason = 'TEXT_DECODE_FAIL'; Text = $null; Encoding = 'unknown' }
        }
    }
}

function Test-LooksLikeBase64Payload {
    param([Parameter(Mandatory)][string]$Text)
    $trim = ($Text -replace '\s','')
    if ($trim.Length -lt 128) { return $false }
    if (($trim.Length % 4) -ne 0) { return $false }
    if ($trim -notmatch '^[A-Za-z0-9+/=]+$') { return $false }
    try {
        $bytes = [Convert]::FromBase64String($trim)
        if ($bytes.Length -lt 64) { return $false }
        $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($decoded -match '(?s)(<html|<!doctype|---\s*$|\{\s*"|module\.exports|export\s+default|title:|layout:|eleventy)') {
            return $true
        }
    }
    catch {}
    return $false
}

function Convert-SmartQuotesToAscii {
    param([Parameter(Mandatory)][string]$Text)
    $map = @{
        ([char]0x2018) = "'"; ([char]0x2019) = "'"; ([char]0x201C) = '"'; ([char]0x201D) = '"';
        ([char]0x00AB) = '"'; ([char]0x00BB) = '"'; ([char]0x2013) = '-'; ([char]0x2014) = '-';
        ([char]0x00A0) = ' '
    }
    $out = $Text
    foreach ($key in $map.Keys) { $out = $out.Replace([string]$key, [string]$map[$key]) }
    return $out
}

function Try-RepairJsonText {
    param([Parameter(Mandatory)][string]$Text)
    $candidate = Convert-SmartQuotesToAscii -Text $Text
    $candidate = [regex]::Replace($candidate, ',(\s*[}\]])', '$1')
    try {
        $null = $candidate | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{ Success = $true; Text = $candidate; Rule = 'JSON_TRAILING_COMMA_SMART_QUOTES' }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Text = $Text; Rule = '' }
    }
}

function Try-RepairYamlLikeText {
    param([Parameter(Mandatory)][string]$Text)
    $candidate = Convert-SmartQuotesToAscii -Text $Text
    $candidate = ($candidate -replace "`t", '  ')
    if ($candidate -ne $Text) {
        return [pscustomobject]@{ Success = $true; Text = $candidate; Rule = 'YAML_SMART_QUOTES_TABS' }
    }
    return [pscustomobject]@{ Success = $false; Text = $Text; Rule = '' }
}

function Try-RepairCodeLikeText {
    param([Parameter(Mandatory)][string]$Text)
    $candidate = Convert-SmartQuotesToAscii -Text $Text
    if ($candidate -ne $Text) {
        return [pscustomobject]@{ Success = $true; Text = $candidate; Rule = 'SMART_QUOTES_ASCII' }
    }
    return [pscustomobject]@{ Success = $false; Text = $Text; Rule = '' }
}

function Invoke-SafeFixForFile {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$FullPath
    )
    if ($NoAutoFix) { return }
    if (-not (Test-IsTextPath -RelativePath $RelativePath)) { return }
    $read = Get-TextReadResult -Path $FullPath
    if (-not $read.Success) { return }
    $text = [string]$read.Text
    $ext = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    $fixed = $null
    if ($ext -eq '.json') {
        $attempt = Try-RepairJsonText -Text $text
        if ($attempt.Success -and $attempt.Text -ne $text) { $fixed = $attempt }
    }
    elseif (@('.yml','.yaml') -contains $ext -or ($ext -eq '.md' -and $text.TrimStart().StartsWith('---'))) {
        $attempt = Try-RepairYamlLikeText -Text $text
        if ($attempt.Success -and $attempt.Text -ne $text) { $fixed = $attempt }
    }
    elseif (@('.js','.njk','.html','.xml','.css','.md','.txt','.svg') -contains $ext -or [System.IO.Path]::GetFileName($RelativePath).ToLowerInvariant().EndsWith('.11tydata.js')) {
        $attempt = Try-RepairCodeLikeText -Text $text
        if ($attempt.Success -and $attempt.Text -ne $text) { $fixed = $attempt }
    }
    if ($null -ne $fixed) {
        $beforeSha = Get-Sha256HexForFile -Path $FullPath
        [System.IO.File]::WriteAllText($FullPath, [string]$fixed.Text, (New-Object System.Text.UTF8Encoding($false)))
        $afterSha = Get-Sha256HexForFile -Path $FullPath
        $script:AutoFixRecords += [pscustomobject]@{
            path       = $RelativePath
            rule       = $fixed.Rule
            before_sha = $beforeSha
            after_sha  = $afterSha
        }
        Write-Log "AUTOFIX applied [$($fixed.Rule)]: $RelativePath"
    }
}

function Validate-BatchContent {
    param([Parameter(Mandatory)][object[]]$Inventory)
    if ($Inventory.Count -eq 0) { throw 'No deployable files found after validation.' }
    $allowed = @()
    $rejected = @()
    foreach ($item in $Inventory) {
        if (Test-ForbiddenPath -RelativePath $item.RelativePath) {
            $reason = 'JUNK_ARTIFACT'
            $rejected += $item
            $script:RejectRecords += [pscustomobject]@{ path = $item.RelativePath; reason = $reason }
            continue
        }
        if (-not (Test-WebOpsPathPolicy -RelativePath $item.RelativePath)) {
            $reason = 'OUT_OF_SCOPE'
            $rejected += $item
            $script:RejectRecords += [pscustomobject]@{ path = $item.RelativePath; reason = $reason }
            continue
        }
        Invoke-SafeFixForFile -RelativePath $item.RelativePath -FullPath $item.FullPath
        if (Test-IsTextPath -RelativePath $item.RelativePath) {
            $read = Get-TextReadResult -Path $item.FullPath
            if (-not $read.Success) {
                $rejected += $item
                $script:RejectRecords += [pscustomobject]@{ path = $item.RelativePath; reason = $read.Reason }
                continue
            }
            if (Test-LooksLikeBase64Payload -Text ([string]$read.Text)) {
                $rejected += $item
                $script:RejectRecords += [pscustomobject]@{ path = $item.RelativePath; reason = 'TEXT_PAYLOAD_NOT_PLAINTEXT' }
                continue
            }
        }
        $allowed += $item
    }
    $script:AcceptedFileCount = $allowed.Count
    $script:RejectedFileCount = $rejected.Count
    $script:AcceptedPaths = @($allowed | Select-Object -ExpandProperty RelativePath)
    if ($rejected.Count -gt 0) {
        $script:RejectedPathSample = (($rejected | Select-Object -First 10 -ExpandProperty RelativePath) -join ', ')
        Write-Log -Level WARN -Message ("WEBOPS policy rejected {0} path(s): {1}" -f $rejected.Count, $script:RejectedPathSample)
    }
    else {
        $script:RejectedPathSample = ''
    }
    if ($allowed.Count -eq 0) { throw 'PATCH BLOCKED: 0 files accepted by WEBOPS policy.' }
    if ($allowed.Count -gt $MaxFiles) { throw "Accepted file count exceeds limit: $($allowed.Count) > $MaxFiles" }
    $totalBytes = ($allowed | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $totalBytes) { $totalBytes = 0 }
    $totalMB = [math]::Round(($totalBytes / 1MB), 2)
    if ($totalMB -gt $MaxTotalMB) { throw "Accepted batch size exceeds limit: ${totalMB}MB > ${MaxTotalMB}MB" }
    $script:BatchFileCount = $allowed.Count
    $script:BatchSizeMB = $totalMB
    Write-Log "Validation OK. AcceptedFiles=$($allowed.Count); RejectedFiles=$($rejected.Count); SizeMB=$totalMB"
    return @($allowed)
}

function Get-RefSha {
    $uri = ('https://api.github.com/repos/{0}/{1}/git/ref/heads/{2}' -f $RepoOwner, $RepoName, $Branch)
    $resp = Invoke-GitHubApi -Method GET -Uri $uri
    return $resp.object.sha
}

function Get-Commit {
    param([Parameter(Mandatory)][string]$Sha)
    $uri = ('https://api.github.com/repos/{0}/{1}/git/commits/{2}' -f $RepoOwner, $RepoName, $Sha)
    return (Invoke-GitHubApi -Method GET -Uri $uri)
}

function Get-BlobShaForFile {
    param([Parameter(Mandatory)][string]$FilePath)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $prefix = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $all = New-Object byte[] ($prefix.Length + $bytes.Length)
    [Array]::Copy($prefix, 0, $all, 0, $prefix.Length)
    [Array]::Copy($bytes, 0, $all, $prefix.Length, $bytes.Length)
    return (Get-Sha1Hex -Bytes $all)
}

function Get-ExistingTreeMap {
    param([Parameter(Mandatory)][string]$TreeSha)
    $uri = ('https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1' -f $RepoOwner, $RepoName, $TreeSha)
    $tree = Invoke-GitHubApi -Method GET -Uri $uri
    $map = @{}
    foreach ($item in $tree.tree) {
        if ($item.type -eq 'blob') { $map[$item.path] = $item.sha }
    }
    return $map
}

function Build-ChangeSummary {
    param(
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][hashtable]$ExistingTreeMap
    )
    $summary = @()
    foreach ($item in $Inventory) {
        $blobSha = Get-BlobShaForFile -FilePath $item.FullPath
        $existingSha = $null
        if ($ExistingTreeMap.ContainsKey($item.RelativePath)) { $existingSha = $ExistingTreeMap[$item.RelativePath] }
        $action = if (-not $existingSha) { 'ADD' } elseif ($existingSha -eq $blobSha) { 'SKIP_SAME' } else { 'UPDATE' }
        $summary += [pscustomobject]@{
            RelativePath = $item.RelativePath
            FullPath     = $item.FullPath
            Action       = $action
            BlobSha      = $blobSha
            ExistingSha  = $existingSha
            Length       = $item.Length
        }
    }
    return @($summary)
}

function New-GitBlob {
    param([Parameter(Mandatory)][string]$FilePath)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $content = [Convert]::ToBase64String($bytes)
    $uri = ('https://api.github.com/repos/{0}/{1}/git/blobs' -f $RepoOwner, $RepoName)
    $body = @{ content = $content; encoding = 'base64' }
    $resp = Invoke-GitHubApi -Method POST -Uri $uri -Body $body
    return $resp.sha
}

function New-TreeEntries {
    param([Parameter(Mandatory)][object[]]$ChangeSummary)
    $entries = @()
    foreach ($entry in $ChangeSummary) {
        if ($entry.Action -eq 'SKIP_SAME') { continue }
        $blobSha = New-GitBlob -FilePath $entry.FullPath
        $entries += @{ path = $entry.RelativePath; mode = '100644'; type = 'blob'; sha = $blobSha }
    }
    return @($entries)
}

function Create-NewTree {
    param(
        [Parameter(Mandatory)][string]$BaseTreeSha,
        [Parameter(Mandatory)][object[]]$Entries
    )
    $uri = ('https://api.github.com/repos/{0}/{1}/git/trees' -f $RepoOwner, $RepoName)
    $body = @{ base_tree = $BaseTreeSha; tree = @($Entries) }
    return (Invoke-GitHubApi -Method POST -Uri $uri -Body $body)
}

function Create-NewCommit {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$TreeSha,
        [Parameter(Mandatory)][string]$ParentSha
    )
    $uri = ('https://api.github.com/repos/{0}/{1}/git/commits' -f $RepoOwner, $RepoName)
    $body = @{ message = $Message; tree = $TreeSha; parents = @($ParentSha) }
    return (Invoke-GitHubApi -Method POST -Uri $uri -Body $body)
}

function Update-BranchRef {
    param([Parameter(Mandatory)][string]$CommitSha)
    $uri = ('https://api.github.com/repos/{0}/{1}/git/refs/heads/{2}' -f $RepoOwner, $RepoName, $Branch)
    $body = @{ sha = $CommitSha; force = $false }
    Invoke-GitHubApi -Method PATCH -Uri $uri -Body $body | Out-Null
}

function Verify-BranchAdvanced {
    param(
        [Parameter(Mandatory)][string]$ExpectedCommitSha,
        [Parameter(Mandatory)][object[]]$ChangeSummary,
        [Parameter(Mandatory)][string]$HeadTreeSha
    )
    $currentHead = Get-RefSha
    if ($currentHead -ne $ExpectedCommitSha) {
        throw "POST_VERIFY_FAIL: HEAD mismatch. Expected=$ExpectedCommitSha Actual=$currentHead"
    }
    $repoMap = Get-ExistingTreeMap -TreeSha $HeadTreeSha
    foreach ($row in $ChangeSummary) {
        if ($row.Action -eq 'SKIP_SAME') { continue }
        if (-not $repoMap.ContainsKey($row.RelativePath)) {
            throw "POST_VERIFY_FAIL: Missing path in repo after commit: $($row.RelativePath)"
        }
        if ($repoMap[$row.RelativePath] -ne $row.BlobSha) {
            throw "POST_VERIFY_FAIL: Blob SHA mismatch for path: $($row.RelativePath)"
        }
    }
}

try {
    try { '' | Set-Content -LiteralPath $script:LogFile -Encoding UTF8 } catch {}
    Acquire-Lock
    Write-Log 'START'
    Write-Log "Repo: $RepoOwner/$RepoName"
    Write-Log "Branch: $Branch"
    Write-Log "Batch root: $script:BatchRoot"
    Write-Log "Working directory: $(Get-Location)"
    Write-Log "Temp root: $TempRoot"

    $script:Config = Load-AgentConfig
    if ($script:Config) { Write-Log 'Config loaded: agent.config.json' }

    $script:GitHubToken = Get-GitHubToken

    $zip = Get-BatchZip
    $script:ZipName = $zip.Name
    $script:ZipSha256 = Get-Sha256HexForFile -Path $zip.FullName
    Write-Log "ZIP: $($zip.FullName)"

    if (Test-AlreadyProcessedZip -Sha256 $script:ZipSha256) {
        $script:FinalStatus = 'SKIPPED_DUPLICATE_ZIP'
        Write-Log -Level WARN -Message 'SKIPPED_DUPLICATE_ZIP: This ZIP SHA256 was already processed earlier. Repo state unchanged.'
        Write-DeployReport
        exit 0
    }

    Expand-BatchZip -ZipPath $zip.FullName
    $script:SourceRoot = Get-AutoRoot -ExpandedRoot $script:BatchExpandDir
    $inventory = Get-FileInventory -SourceRoot $script:SourceRoot
    $inventory = @(Validate-BatchContent -Inventory $inventory)

    $script:BaseCommitSha = Get-RefSha
    Write-Log "Base commit SHA: $script:BaseCommitSha"
    $baseCommit = Get-Commit -Sha $script:BaseCommitSha
    $script:BaseTreeSha = $baseCommit.tree.sha
    Write-Log "Base tree SHA: $script:BaseTreeSha"

    $existingTreeMap = Get-ExistingTreeMap -TreeSha $script:BaseTreeSha
    $changeSummary = Build-ChangeSummary -Inventory $inventory -ExistingTreeMap $existingTreeMap
    $script:PreviewADD = @($changeSummary | Where-Object { $_.Action -eq 'ADD' }).Count
    $script:PreviewUPD = @($changeSummary | Where-Object { $_.Action -eq 'UPDATE' }).Count
    $script:PreviewSKIP = @($changeSummary | Where-Object { $_.Action -eq 'SKIP_SAME' }).Count
    Write-Log ("Preview: ADD={0} UPDATE={1} SKIP_SAME={2}" -f $script:PreviewADD, $script:PreviewUPD, $script:PreviewSKIP)
    foreach ($row in ($changeSummary | Select-Object -First 50)) { Write-Log ("{0}: {1}" -f $row.Action, $row.RelativePath) }

    if ($WhatIfOnly) {
        $script:FinalStatus = 'WHATIF'
        Write-Log 'WhatIfOnly set. No commit created.' -Level WARN
        Write-DeployReport
        exit 0
    }

    $entries = @(New-TreeEntries -ChangeSummary $changeSummary)
    if ($entries.Count -eq 0) {
        $script:FinalStatus = 'PASS_NO_CHANGES'
        Write-Log 'No effective changes detected. Nothing to commit. Repo state unchanged.' -Level WARN
        Write-DeployReport
        exit 0
    }

    $newTree = Create-NewTree -BaseTreeSha $script:BaseTreeSha -Entries $entries
    $script:NewTreeSha = $newTree.sha
    Write-Log "New tree SHA: $script:NewTreeSha"

    $msg = "WEBOPS macro-batch+autofix: $($zip.BaseName) | files=$($entries.Count)"
    $newCommit = Create-NewCommit -Message $msg -TreeSha $script:NewTreeSha -ParentSha $script:BaseCommitSha
    $script:NewCommitSha = $newCommit.sha
    Write-Log "New commit SHA: $script:NewCommitSha"

    Update-BranchRef -CommitSha $script:NewCommitSha
    Write-Log 'Branch updated.'

    $headCommit = Get-Commit -Sha $script:NewCommitSha
    Verify-BranchAdvanced -ExpectedCommitSha $script:NewCommitSha -ChangeSummary $changeSummary -HeadTreeSha $headCommit.tree.sha
    Write-Log 'Post-commit verify passed.'

    $doneTarget = Join-Path $DoneDir $zip.Name
    Move-Item -LiteralPath $zip.FullName -Destination $doneTarget -Force
    Write-Log "ZIP moved to done: $doneTarget"
    Mark-ProcessedZip -Sha256 $script:ZipSha256

    $script:FinalStatus = 'PASS'
    Write-Log 'BATCH COMMIT DONE'
    Write-DeployReport
    exit 0
}
catch {
    Fail-Run -Reason $_.Exception.Message -ExitCode 1
}
finally {
    Release-Lock
}
