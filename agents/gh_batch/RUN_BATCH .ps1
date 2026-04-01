[CmdletBinding()]
param(
    [string]$InboxDir = '',
    [string]$DoneDir  = '',
    [string]$LogsDir  = '',
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

    if ([string]::IsNullOrWhiteSpace($relative)) {
        throw "Resolved empty relative path for '$FullPath'"
    }

    if ($relative.StartsWith('/')) {
        $relative = $relative.TrimStart('/')
    }

    if ($relative -match '^[A-Za-z]:') {
        throw "Absolute drive path not allowed: $relative"
    }

    if ($relative.StartsWith('../') -or $relative -eq '..' -or $relative -like '*/../*') {
        throw "Path traversal not allowed: $relative"
    }

    return $relative
}

function Test-AllowedBatchPath {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    if ($RelativePath -eq 'README.txt') { return $true }
    if ($RelativePath -like 'src/*') { return $true }

    return $false
}

function Get-BatchInventory {
    param(
        [Parameter(Mandatory)][string]$SourceRoot
    )

    $items = @()
    $dups = @{}
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force)

    foreach ($file in $files) {
        $relativePath = Normalize-RelativePath -BasePath $SourceRoot -FullPath $file.FullName
        $key = $relativePath.ToLowerInvariant()

        if ($dups.ContainsKey($key)) {
            throw "Duplicate path after normalization: $relativePath"
        }

        $dups[$key] = $true

        $items += [pscustomobject]@{
            RelativePath = $relativePath
            FullPath     = $file.FullName
            Length       = [int64]$file.Length
        }
    }

    return @($items)
}

function Validate-BatchPolicy {
    param(
        [Parameter(Mandatory)][object[]]$Inventory
    )

    $allowed = @()
    $rejected = @()

    foreach ($item in $Inventory) {
        if (Test-AllowedBatchPath -RelativePath $item.RelativePath) {
            $allowed += $item
        }
        else {
            $rejected += $item
        }
    }

    if ($rejected.Count -gt 0) {
        $sample = ($rejected | Select-Object -ExpandProperty RelativePath | Select-Object -First 20) -join ', '
        throw "FAIL_POLICY: forbidden path(s) detected: $sample"
    }

    if ($allowed.Count -eq 0) {
        throw 'FAIL_POLICY: no deployable files found. Batch must contain README.txt and/or src/**'
    }

    return @($allowed)
}

$scriptRoot = Resolve-ScriptRoot
$repoRoot   = Split-Path -Parent (Split-Path -Parent $scriptRoot)

if ([string]::IsNullOrWhiteSpace($InboxDir)) {
    $InboxDir = Join-Path $repoRoot 'inbox\processing'
}
if ([string]::IsNullOrWhiteSpace($DoneDir)) {
    $DoneDir = Join-Path $repoRoot 'done'
}
if ([string]::IsNullOrWhiteSpace($LogsDir)) {
    $LogsDir = Join-Path $repoRoot 'logs'
}

$TempRoot = Get-UsableTempRoot -PreferredPath $TempRoot

New-Dir -Path $InboxDir
New-Dir -Path $DoneDir
New-Dir -Path $LogsDir
New-Dir -Path $TempRoot

$runStamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile        = Join-Path $LogsDir ("RUN_BATCH_{0}.log" -f $runStamp)
$jsonReportFile = Join-Path $LogsDir ("RUN_REPORT_{0}.json" -f $runStamp)
$expandRoot     = Join-Path $TempRoot ("EXPAND_{0}" -f $runStamp)

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Write-RunReport {
    param(
        [Parameter(Mandatory)][string]$Status,
        [AllowEmptyString()][string]$FailReason = '',
        [string]$ZipName = '',
        [string]$ZipSourcePath = '',
        [string]$ZipDonePath = '',
        [int]$ExpandedFileCount = 0,
        [string]$ExpandedRoot = '',
        [string]$LogFilePath = '',
        [string[]]$AcceptedPaths = @(),
        [string[]]$RejectedPaths = @()
    )

    $payload = [ordered]@{
        status              = $Status
        fail_reason         = $FailReason
        zip_name            = $ZipName
        inbox_dir           = $InboxDir
        done_dir            = $DoneDir
        logs_dir            = $LogsDir
        zip_source_path     = $ZipSourcePath
        zip_done_path       = $ZipDonePath
        expanded_file_count = $ExpandedFileCount
        expanded_root       = $ExpandedRoot
        accepted_paths      = @($AcceptedPaths)
        rejected_paths      = @($RejectedPaths)
        log_file            = $LogFilePath
        timestamp           = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $jsonReportFile -Value $json -Encoding UTF8
}

function Get-OldestZip {
    $zips = @()

    if (Test-Path -LiteralPath $InboxDir) {
        $zips = @(Get-ChildItem -LiteralPath $InboxDir -File -Filter '*.zip' | Sort-Object LastWriteTime)
    }

    if ($zips.Count -eq 0) {
        return $null
    }

    return $zips[0]
}

$zip = $null
$zipName = ''
$zipSourcePath = ''
$zipDonePath = ''
$expandedFileCount = 0
$acceptedPaths = @()
$rejectedPaths = @()

try {
    Write-Log -Message 'START'
    Write-Log -Message ("Repo root: {0}" -f $repoRoot)
    Write-Log -Message ("Queue dir: {0}" -f $InboxDir)
    Write-Log -Message ("Done dir: {0}" -f $DoneDir)
    Write-Log -Message ("Logs dir: {0}" -f $LogsDir)
    Write-Log -Message ("Temp root: {0}" -f $TempRoot)

    $zip = Get-OldestZip

    if ($null -eq $zip) {
        Write-Log -Message 'No ZIP found in processing queue.' -Level WARN
        Write-RunReport `
            -Status 'PASS_NO_JOB' `
            -FailReason '' `
            -ZipName '' `
            -ZipSourcePath '' `
            -ZipDonePath '' `
            -ExpandedFileCount 0 `
            -ExpandedRoot '' `
            -LogFilePath $logFile `
            -AcceptedPaths @() `
            -RejectedPaths @()
        exit 0
    }

    $zipName = $zip.Name
    $zipSourcePath = $zip.FullName

    Write-Log -Message ("Selected ZIP: {0}" -f $zipSourcePath)

    if ($WhatIfOnly) {
        Write-Log -Message 'WhatIfOnly set. No file move will be performed.' -Level WARN
        Write-RunReport `
            -Status 'WHATIF' `
            -FailReason '' `
            -ZipName $zipName `
            -ZipSourcePath $zipSourcePath `
            -ZipDonePath '' `
            -ExpandedFileCount 0 `
            -ExpandedRoot '' `
            -LogFilePath $logFile `
            -AcceptedPaths @() `
            -RejectedPaths @()
        exit 0
    }

    if (Test-Path -LiteralPath $expandRoot) {
        Remove-Item -LiteralPath $expandRoot -Recurse -Force
    }
    New-Dir -Path $expandRoot

    Expand-Archive -LiteralPath $zipSourcePath -DestinationPath $expandRoot -Force
    Write-Log -Message ("ZIP expanded to: {0}" -f $expandRoot)

    $inventory = @(Get-BatchInventory -SourceRoot $expandRoot)
    $expandedFileCount = $inventory.Count
    Write-Log -Message ("Expanded file count: {0}" -f $expandedFileCount)

    $validated = @(Validate-BatchPolicy -Inventory $inventory)
    $acceptedPaths = @($validated | Select-Object -ExpandProperty RelativePath)
    $rejectedPaths = @()

    if ($acceptedPaths.Count -gt 0) {
        Write-Log -Message ("Accepted paths: {0}" -f ($acceptedPaths -join ', '))
    }

    $zipDonePath = Join-Path $DoneDir $zipName
    if (Test-Path -LiteralPath $zipDonePath) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $zipDonePath = Join-Path $DoneDir ("{0}_{1}.zip" -f [System.IO.Path]::GetFileNameWithoutExtension($zipName), $stamp)
    }

    Move-Item -LiteralPath $zipSourcePath -Destination $zipDonePath -Force
    Write-Log -Message ("ZIP moved to done: {0}" -f $zipDonePath)

    Write-RunReport `
        -Status 'PASS' `
        -FailReason '' `
        -ZipName $zipName `
        -ZipSourcePath $zipSourcePath `
        -ZipDonePath $zipDonePath `
        -ExpandedFileCount $expandedFileCount `
        -ExpandedRoot $expandRoot `
        -LogFilePath $logFile `
        -AcceptedPaths $acceptedPaths `
        -RejectedPaths $rejectedPaths

    Write-Log -Message 'DONE'
    exit 0
}
catch {
    $errText = $_.Exception.Message

    if ($errText -match 'FAIL_POLICY:') {
        $status = 'FAIL_POLICY'
    }
    else {
        $status = 'FAIL_RUNTIME'
    }

    Write-Log -Message $errText -Level ERROR

    Write-RunReport `
        -Status $status `
        -FailReason $errText `
        -ZipName $zipName `
        -ZipSourcePath $zipSourcePath `
        -ZipDonePath $zipDonePath `
        -ExpandedFileCount $expandedFileCount `
        -ExpandedRoot $expandRoot `
        -LogFilePath $logFile `
        -AcceptedPaths $acceptedPaths `
        -RejectedPaths $rejectedPaths

    exit 1
}
