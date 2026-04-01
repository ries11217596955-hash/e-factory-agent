[CmdletBinding()]
param(
    [string]$ZipPath = '',
    [string]$LogsDir = '',
    [string]$TempRoot = '',
    [switch]$WhatIfOnly
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
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-UsableTempRoot {
    param(
        [string]$PreferredPath
    )

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        $candidates += $PreferredPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $candidates += (Join-Path $env:TEMP 'GH_BATCH_TMP')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TMP)) {
        $candidates += (Join-Path $env:TMP 'GH_BATCH_TMP')
    }

    try {
        $candidates += (Join-Path ([System.IO.Path]::GetTempPath()) 'GH_BATCH_TMP')
    }
    catch {
    }

    $candidates += (Join-Path (Resolve-ScriptRoot) '_tmp')

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            New-Dir -Path $candidate
            $probe = Join-Path $candidate ('probe_{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $candidate
        }
        catch {
        }
    }

    throw 'Could not find a writable temp root.'
}

function New-RunResult {
    return [ordered]@{
        status               = 'FAIL_RUNTIME'
        outcome_class        = 'FAIL_RUNTIME'
        reason_code          = 'INTERNAL_INIT'
        execution_mode       = 'FAIL_RUNTIME'
        zip_name             = ''
        zip_source_path      = ''
        batch_hash           = ''
        expanded_file_count  = 0
        expanded_root        = ''
        accepted_paths       = @()
        rejected_paths       = @()
        forbidden_paths      = @()
        allowed_paths_only   = $false
        profile              = 'UNKNOWN'
        profile_reason       = ''
        apply_changed        = $false
        staged_targets       = @()
        commit_created       = $false
        commit_sha           = ''
        fail_reason          = ''
        message              = ''
        log_file             = ''
        report_file          = ''
        run_id               = ''
        timestamp            = ''
    }
}

function New-ResultTerminal {
    param(
        [Parameter(Mandatory)][hashtable]$Result,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$OutcomeClass,
        [Parameter(Mandatory)][string]$ReasonCode,
        [Parameter(Mandatory)][string]$ExecutionMode,
        [Parameter(Mandatory)][string]$Message
    )

    $Result['status'] = $Status
    $Result['outcome_class'] = $OutcomeClass
    $Result['reason_code'] = $ReasonCode
    $Result['execution_mode'] = $ExecutionMode
    $Result['message'] = $Message
    if ($OutcomeClass -eq 'FAIL_POLICY' -or $OutcomeClass -eq 'FAIL_RUNTIME') {
        $Result['fail_reason'] = $Message
    }
}

function Get-FileSha256Hex {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Get-Command -Name Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $stream = $null
    $sha = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant())
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if ($null -ne $sha) {
            $sha.Dispose()
        }
    }
}

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    $path = $RelativePath -replace '\\','/'
    $path = $path.Trim()

    while ($path.StartsWith('/')) {
        $path = $path.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'FAIL_POLICY: empty relative path.'
    }

    if ($path -match '^[A-Za-z]:') {
        throw "FAIL_POLICY: absolute drive path not allowed: $path"
    }

    if ($path.StartsWith('../') -or $path.StartsWith('..\') -or $path -eq '..' -or $path -like '*/../*' -or $path -like '*\..\*') {
        throw "FAIL_POLICY: path traversal not allowed: $path"
    }

    return $path
}

function Get-AgentConfig {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    $configPath = Join-Path $ScriptRoot 'agent.config.json'
    $config = [ordered]@{
        allowed_scope    = @('src/')
        text_extensions  = @('.md','.html','.njk','.json','.js','.css','.xml','.txt','.yml','.yaml','.svg','.csv','.11tydata.js')
        forbidden_paths  = @('_site','node_modules','.git','.cache','dist','coverage','tmp','temp')
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        return $config
    }

    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json

        if ($parsed.allowed_scope) {
            $config['allowed_scope'] = @($parsed.allowed_scope)
        }
        if ($parsed.text_extensions) {
            $config['text_extensions'] = @($parsed.text_extensions)
        }
        if ($parsed.forbidden_paths) {
            $config['forbidden_paths'] = @($parsed.forbidden_paths)
        }
    }
    catch {
    }

    return $config
}

function Get-ZipEntries {
    param(
        [Parameter(Mandatory)][string]$ZipFilePath
    )

    if (-not (Test-Path -LiteralPath $ZipFilePath)) {
        throw "FAIL_RUNTIME: ZIP_NOT_FOUND: $ZipFilePath"
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    }
    catch {
        throw 'FAIL_RUNTIME: ZIP_LIB_LOAD_FAILED'
    }

    $archive = $null
    $entries = @()

    try {
        $archive = [System.IO.Compression.ZipFile]::Open(
            $ZipFilePath,
            [System.IO.Compression.ZipArchiveMode]::Read
        )
    }
    catch {
        throw "FAIL_RUNTIME: ZIP_OPEN_FAILED: $ZipFilePath"
    }

    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.FullName)) {
                continue
            }

            $entryName = $entry.FullName -replace '\\','/'
            if ($entryName.EndsWith('/')) {
                continue
            }

            $normalized = Normalize-RelativePath -RelativePath $entryName

            $entries += [pscustomobject]@{
                RelativePath = $normalized
                Length       = [int64]$entry.Length
            }
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }

    if ($entries.Count -eq 0) {
        throw 'FAIL_POLICY: ARCHIVE_EMPTY_OR_UNREADABLE'
    }

    return @($entries)
}

function Get-WrapperNormalizedEntries {
    param(
        [Parameter(Mandatory)][object[]]$Entries
    )

    $segments = @()
    foreach ($entry in $Entries) {
        $parts = @($entry.RelativePath.Split('/'))
        if ($parts.Count -gt 1) {
            $segments += $parts[0]
        }
        else {
            $segments += ''
        }
    }

    $distinct = @($segments | Select-Object -Unique)

    if ($distinct.Count -ne 1) {
        return @($Entries)
    }

    $wrapper = [string]$distinct[0]
    if ([string]::IsNullOrWhiteSpace($wrapper)) {
        return @($Entries)
    }

    $normalized = @()
    foreach ($entry in $Entries) {
        $path = [string]$entry.RelativePath
        if ($path.StartsWith($wrapper + '/')) {
            $stripped = $path.Substring($wrapper.Length + 1)
            if ([string]::IsNullOrWhiteSpace($stripped)) {
                continue
            }
            $normalized += [pscustomobject]@{
                RelativePath = $stripped
                Length       = [int64]$entry.Length
            }
        }
        else {
            return @($Entries)
        }
    }

    return @($normalized)
}

function Test-AllowedBatchPath {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][hashtable]$Config
    )

    if ($RelativePath -eq 'README.txt') { return $true }
    if ($RelativePath -eq 'README.md')  { return $true }

    foreach ($scope in @($Config['allowed_scope'])) {
        $normalizedScope = ($scope -replace '\\','/').Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedScope)) {
            continue
        }

        if (-not $normalizedScope.EndsWith('/')) {
            $normalizedScope = $normalizedScope + '/'
        }

        if ($RelativePath.StartsWith($normalizedScope, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-PathClassification {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][hashtable]$Config
    )

    $accepted = @()
    $rejected = @()

    foreach ($entry in $Entries) {
        if (Test-AllowedBatchPath -RelativePath $entry.RelativePath -Config $Config) {
            $accepted += [string]$entry.RelativePath
        }
        else {
            $rejected += [string]$entry.RelativePath
        }
    }

    return [ordered]@{
        AcceptedPaths    = @($accepted)
        RejectedPaths    = @($rejected)
        AllowedPathsOnly = ($rejected.Count -eq 0 -and $accepted.Count -gt 0)
    }
}

function Get-FileExtensionNormalized {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    $path = $RelativePath.ToLowerInvariant()

    if ($path.EndsWith('.11tydata.js')) {
        return '.11tydata.js'
    }

    return ([System.IO.Path]::GetExtension($path)).ToLowerInvariant()
}

function Get-ProfileClassification {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string[]]$AcceptedPaths,
        [Parameter(Mandatory)][hashtable]$Config
    )

    if ($AcceptedPaths.Count -eq 0) {
        return [ordered]@{
            Profile = 'UNSUPPORTED_PROFILE'
            Reason  = 'NO_ACCEPTED_PATHS'
        }
    }

    if ($AcceptedPaths.Count -gt 10) {
        return [ordered]@{
            Profile = 'UNSUPPORTED_PROFILE'
            Reason  = 'TOO_MANY_FILES'
        }
    }

    $dirSet = @{}
    foreach ($path in $AcceptedPaths) {
        $parent = [System.IO.Path]::GetDirectoryName(($path -replace '/','\\'))
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $dirSet[$parent.ToLowerInvariant()] = $true
        }
    }

    if ($dirSet.Keys.Count -gt 5) {
        return [ordered]@{
            Profile = 'UNSUPPORTED_PROFILE'
            Reason  = 'TOO_MANY_DIRECTORIES'
        }
    }

    $allowedExtSet = @{}
    foreach ($ext in @($Config['text_extensions'])) {
        $allowedExtSet[[string]$ext.ToLowerInvariant()] = $true
    }

    foreach ($path in $AcceptedPaths) {
        $lower = $path.ToLowerInvariant()

        if ($lower -eq 'readme.txt' -or $lower -eq 'readme.md') {
            continue
        }

        $ext = Get-FileExtensionNormalized -RelativePath $path
        if ([string]::IsNullOrWhiteSpace($ext)) {
            return [ordered]@{
                Profile = 'UNSUPPORTED_PROFILE'
                Reason  = ('NO_EXTENSION:{0}' -f $path)
            }
        }

        if (-not $allowedExtSet.ContainsKey($ext)) {
            return [ordered]@{
                Profile = 'UNSUPPORTED_PROFILE'
                Reason  = ('UNSUPPORTED_EXTENSION:{0}' -f $ext)
            }
        }
    }

    return [ordered]@{
        Profile = 'SAFE_MICRO_FIX_V1'
        Reason  = 'TEXT_ONLY_ALLOWED_SCOPE'
    }
}

function Expand-ZipToStaging {
    param(
        [Parameter(Mandatory)][string]$ZipFilePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Dir -Path $DestinationPath
    Expand-Archive -LiteralPath $ZipFilePath -DestinationPath $DestinationPath -Force
}

function Get-InventoryFromExpandedRoot {
    param(
        [Parameter(Mandatory)][string]$SourceRoot
    )

    $items = @()
    $dups = @{}
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force)

    foreach ($file in $files) {
        $baseFull = [System.IO.Path]::GetFullPath($SourceRoot)
        $fileFull = [System.IO.Path]::GetFullPath($file.FullName)

        if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $baseFull = $baseFull + [System.IO.Path]::DirectorySeparatorChar
        }

        if (-not $fileFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "FAIL_RUNTIME: expanded file outside staging root: $fileFull"
        }

        $relative = $fileFull.Substring($baseFull.Length) -replace '\\','/'
        $relative = Normalize-RelativePath -RelativePath $relative
        $key = $relative.ToLowerInvariant()

        if ($dups.ContainsKey($key)) {
            throw "FAIL_POLICY: duplicate path after normalization: $relative"
        }

        $dups[$key] = $true

        $items += [pscustomobject]@{
            RelativePath = $relative
            FullPath     = $file.FullName
            Length       = [int64]$file.Length
        }
    }

    return @($items)
}

function Copy-AllowedFilesToRepo {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string[]]$AcceptedPaths,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $copied = @()

    foreach ($relativePath in $AcceptedPaths) {
        $sourcePath = Join-Path $StagingRoot ($relativePath -replace '/','\\')
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "FAIL_RUNTIME: accepted file missing in staging: $relativePath"
        }

        $targetPath = Join-Path $RepoRoot ($relativePath -replace '/','\\')
        $targetDir = Split-Path -Parent $targetPath
        if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
            New-Dir -Path $targetDir
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $copied += $relativePath
    }

    return @($copied)
}

function Get-GitStatusLines {
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    Push-Location $RepoRoot
    try {
        $output = & git status --porcelain
        if ($LASTEXITCODE -ne 0) {
            throw 'git status failed.'
        }

        if ($null -eq $output) {
            return @()
        }

        return @($output)
    }
    finally {
        Pop-Location
    }
}

$scriptRoot = Resolve-ScriptRoot
$repoRoot   = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$config     = Get-AgentConfig -ScriptRoot $scriptRoot

if ([string]::IsNullOrWhiteSpace($LogsDir)) {
    $LogsDir = Join-Path $repoRoot 'logs'
}

$TempRoot = Get-UsableTempRoot -PreferredPath $TempRoot

New-Dir -Path $LogsDir
New-Dir -Path $TempRoot

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$runId    = [guid]::NewGuid().ToString('N')

$logFile        = Join-Path $LogsDir ("RUN_BATCH_{0}_{1}.log" -f $runStamp, $runId)
$jsonReportFile = Join-Path $LogsDir ("RUN_REPORT_{0}_{1}.json" -f $runStamp, $runId)
$expandRoot     = Join-Path $TempRoot ("EXPAND_{0}_{1}" -f $runStamp, $runId)

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Write-RunReport {
    param(
        [Parameter(Mandatory)][hashtable]$Result
    )

    $Result['log_file'] = $logFile
    $Result['report_file'] = $jsonReportFile
    $Result['run_id'] = $runId
    $Result['timestamp'] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')

    $json = $Result | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $jsonReportFile -Value $json -Encoding UTF8
}

$result = New-RunResult
$result['log_file'] = $logFile
$result['report_file'] = $jsonReportFile
$result['run_id'] = $runId

try {
    Write-Log -Message 'START'
    Write-Log -Message ("Repo root: {0}" -f $repoRoot)
    Write-Log -Message ("Logs dir: {0}" -f $LogsDir)
    Write-Log -Message ("Temp root: {0}" -f $TempRoot)
    Write-Log -Message ("Run id: {0}" -f $runId)

    if ([string]::IsNullOrWhiteSpace($ZipPath)) {
        New-ResultTerminal -Result $result `
            -Status 'PASS' `
            -OutcomeClass 'PASS' `
            -ReasonCode 'NO_JOB' `
            -ExecutionMode 'NO_WORK' `
            -Message 'No ZIP path supplied.'
        Write-RunReport -Result $result
        exit 0
    }

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        New-ResultTerminal -Result $result `
            -Status 'FAIL_RUNTIME' `
            -OutcomeClass 'FAIL_RUNTIME' `
            -ReasonCode 'ZIP_NOT_FOUND' `
            -ExecutionMode 'FAIL_RUNTIME' `
            -Message ("ZIP not found: {0}" -f $ZipPath)
        Write-RunReport -Result $result
        exit 0
    }

    $zipName = [System.IO.Path]::GetFileName($ZipPath)
    $result['zip_name'] = $zipName
    $result['zip_source_path'] = $ZipPath
    $result['batch_hash'] = Get-FileSha256Hex -Path $ZipPath

    Write-Log -Message ("Selected ZIP: {0}" -f $ZipPath)
    Write-Log -Message ("Batch hash: {0}" -f $result['batch_hash'])

    if ($WhatIfOnly) {
        New-ResultTerminal -Result $result `
            -Status 'PASS' `
            -OutcomeClass 'PASS' `
            -ReasonCode 'WHATIF' `
            -ExecutionMode 'NO_WORK' `
            -Message 'WhatIfOnly set. No validation or apply performed.'
        Write-RunReport -Result $result
        exit 0
    }

    Write-Log -Message 'Reading ZIP entries...'
    $entries = @(Get-ZipEntries -ZipFilePath $ZipPath)

    $entries = @(Get-WrapperNormalizedEntries -Entries $entries)
    $result['expanded_file_count'] = $entries.Count
    Write-Log -Message ("Archive entries after normalization: {0}" -f $entries.Count)

    $pathClass = Get-PathClassification -Entries $entries -Config $config
    $result['accepted_paths'] = @($pathClass['AcceptedPaths'])
    $result['rejected_paths'] = @($pathClass['RejectedPaths'])
    $result['forbidden_paths'] = @($pathClass['RejectedPaths'])
    $result['allowed_paths_only'] = [bool]$pathClass['AllowedPathsOnly']

    if (-not $result['allowed_paths_only']) {
        $sample = @($result['rejected_paths'] | Select-Object -First 20)
        New-ResultTerminal -Result $result `
            -Status 'FAIL_POLICY' `
            -OutcomeClass 'FAIL_POLICY' `
            -ReasonCode 'FORBIDDEN_PATH' `
            -ExecutionMode 'REJECT_POLICY' `
            -Message ("Forbidden path(s) detected: {0}" -f ($sample -join ', '))
        Write-RunReport -Result $result
        exit 0
    }

    $profileClass = Get-ProfileClassification -Entries $entries -AcceptedPaths @($result['accepted_paths']) -Config $config
    $result['profile'] = [string]$profileClass['Profile']
    $result['profile_reason'] = [string]$profileClass['Reason']

    if ($result['profile'] -ne 'SAFE_MICRO_FIX_V1') {
        New-ResultTerminal -Result $result `
            -Status 'FAIL_POLICY' `
            -OutcomeClass 'FAIL_POLICY' `
            -ReasonCode 'UNSUPPORTED_PROFILE' `
            -ExecutionMode 'REJECT_POLICY' `
            -Message ("Batch profile unsupported for v1: {0}" -f $result['profile_reason'])
        Write-RunReport -Result $result
        exit 0
    }

    Write-Log -Message ("Profile matched: {0}" -f $result['profile'])
    Write-Log -Message ("Accepted paths: {0}" -f (($result['accepted_paths']) -join ', '))

    Expand-ZipToStaging -ZipFilePath $ZipPath -DestinationPath $expandRoot
    $expandedInventory = @(Get-InventoryFromExpandedRoot -SourceRoot $expandRoot)
    $expandedInventory = @(Get-WrapperNormalizedEntries -Entries $expandedInventory)

    $expandedMap = @{}
    foreach ($entry in $expandedInventory) {
        $expandedMap[[string]$entry.RelativePath.ToLowerInvariant()] = $entry
    }

    foreach ($acceptedPath in @($result['accepted_paths'])) {
        $key = [string]$acceptedPath.ToLowerInvariant()
        if (-not $expandedMap.ContainsKey($key)) {
            New-ResultTerminal -Result $result `
                -Status 'FAIL_RUNTIME' `
                -OutcomeClass 'FAIL_RUNTIME' `
                -ReasonCode 'EXPANDED_PATH_MISMATCH' `
                -ExecutionMode 'FAIL_RUNTIME' `
                -Message ("Expanded archive path mismatch for accepted path: {0}" -f $acceptedPath)
            Write-RunReport -Result $result
            exit 0
        }
    }

    $result['expanded_root'] = $expandRoot
    $copied = Copy-AllowedFilesToRepo -StagingRoot $expandRoot -AcceptedPaths @($result['accepted_paths']) -RepoRoot $repoRoot
    $result['staged_targets'] = @($copied)

    $gitStatusLines = @(Get-GitStatusLines -RepoRoot $repoRoot)
    $result['apply_changed'] = ($gitStatusLines.Count -gt 0)

    if (-not $result['apply_changed']) {
        New-ResultTerminal -Result $result `
            -Status 'PASS' `
            -OutcomeClass 'PASS' `
            -ReasonCode 'NO_EFFECT_OK' `
            -ExecutionMode 'AUTO_APPLY' `
            -Message 'Batch valid but produced no changes (idempotent).'
        Write-RunReport -Result $result
        exit 0
    }

    New-ResultTerminal -Result $result `
        -Status 'PASS' `
        -OutcomeClass 'PASS' `
        -ReasonCode 'SAFE_MICRO_FIX_APPLIED' `
        -ExecutionMode 'AUTO_APPLY' `
        -Message 'Safe micro-fix batch applied to repository working tree.'
    Write-RunReport -Result $result
    Write-Log -Message 'DONE'
    exit 0
}
catch {
    $errMessage = $_.Exception.Message
    Write-Log -Message $errMessage -Level ERROR

    $reasonCode = 'UNHANDLED_EXCEPTION'
    if ($errMessage -like 'FAIL_POLICY:*') {
        $reasonCode = 'ARCHIVE_SHAPE'
        New-ResultTerminal -Result $result `
            -Status 'FAIL_POLICY' `
            -OutcomeClass 'FAIL_POLICY' `
            -ReasonCode $reasonCode `
            -ExecutionMode 'REJECT_POLICY' `
            -Message $errMessage
    }
    else {
        if ($errMessage -like '*ZIP_LIB_LOAD_FAILED*') {
            $reasonCode = 'ZIP_LIB_LOAD_FAILED'
        }
        elseif ($errMessage -like '*ZIP_OPEN_FAILED*') {
            $reasonCode = 'ZIP_OPEN_FAILED'
        }
        elseif ($errMessage -like '*ZIP_NOT_FOUND*') {
            $reasonCode = 'ZIP_NOT_FOUND'
        }
        elseif ($errMessage -like '*git status failed*') {
            $reasonCode = 'GIT_STATUS_FAILED'
        }
        elseif ($errMessage -like '*Expand-Archive*' -or $errMessage -like '*archive*') {
            $reasonCode = 'UNPACK_FAILED'
        }
        elseif ($errMessage -like '*Copy-Item*' -or $errMessage -like '*accepted file missing*') {
            $reasonCode = 'APPLY_FAILED'
        }

        New-ResultTerminal -Result $result `
            -Status 'FAIL_RUNTIME' `
            -OutcomeClass 'FAIL_RUNTIME' `
            -ReasonCode $reasonCode `
            -ExecutionMode 'FAIL_RUNTIME' `
            -Message $errMessage
    }

    Write-RunReport -Result $result
    exit 0
}
