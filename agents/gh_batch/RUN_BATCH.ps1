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
    if ($RelativePath -eq 'README.md')  { return $true }
    if ($RelativePath -like 'src/*')    { return $true }

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
        throw 'FAIL_POLICY: no deployable files found. Batch must contain README and/or src/**'
    }

    return @($allowed)
}

$scriptRoot = Resolve-ScriptRoot
$repoRoot   = Split-Path -Parent (Split-Path -Parent $scriptRoot)

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
        [Parameter(Mandatory)][string]$Status,
        [AllowEmptyString()][string]$FailReason = '',
        [string]$ZipName = '',
        [string]$ZipSourcePath = '',
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
        zip_source_path     = $ZipSourcePath
        expanded_file_count = $ExpandedFileCount
        expanded_root       = $ExpandedRoot
        accepted_paths      = @($AcceptedPaths)
        rejected_paths      = @($RejectedPaths)
        log_file            = $LogFilePath
        report_file         = $jsonReportFile
        run_id              = $runId
        timestamp           = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
    }

    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $jsonReportFile -Value $json -Encoding UTF8
}

$zipName = ''
$expandedFileCount = 0
$acceptedPaths = @()
$rejectedPaths = @()

try {
    Write-Log -Message 'START'
    Write-Log -Message ("Repo root: {0}" -f $repoRoot)
    Write-Log -Message ("Logs dir: {0}" -f $LogsDir)
    Write-Log -Message ("Temp root: {0}" -f $TempRoot)
    Write-Log -Message ("Run id: {0}" -f $runId)

    if ([string]::IsNullOrWhiteSpace($ZipPath)) {
        Write-RunReport `
            -Status 'PASS_NO_JOB' `
            -FailReason '' `
            -ZipName '' `
            -ZipSourcePath '' `
            -ExpandedFileCount 0 `
            -ExpandedRoot '' `
            -LogFilePath $logFile `
            -AcceptedPaths @() `
            -RejectedPaths @()
        exit 0
    }

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        throw "FAIL_RUNTIME: ZIP not found: $ZipPath"
    }

    $zipName = [System.IO.Path]::GetFileName($ZipPath)

    Write-Log -Message ("Selected ZIP: {0}" -f $ZipPath)

    if ($WhatIfOnly) {
        Write-Log -Message 'WhatIfOnly set. No validation will be performed.' -Level WARN
        Write-RunReport `
            -Status 'WHATIF' `
            -FailReason '' `
            -ZipName $zipName `
            -ZipSourcePath $ZipPath `
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

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $expandRoot -Force
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

    Write-RunReport `
        -Status 'PASS' `
        -FailReason '' `
        -ZipName $zipName `
        -ZipSourcePath $ZipPath `
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
        -ZipSourcePath $ZipPath `
        -ExpandedFileCount $expandedFileCount `
        -ExpandedRoot $expandRoot `
        -LogFilePath $logFile `
        -AcceptedPaths $acceptedPaths `
        -RejectedPaths $rejectedPaths

    exit 1
}
