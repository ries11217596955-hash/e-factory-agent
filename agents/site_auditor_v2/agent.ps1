[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Mode,
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/modules/util_io.ps1"
. "$PSScriptRoot/modules/util_json.ps1"

function Get-DeterministicRunKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $input = "{0}|{1}" -f $Mode.Trim().ToUpperInvariant(), $BaseUrl.Trim().ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($input)
    $hashBytes = [Security.Cryptography.SHA256]::HashData($bytes)
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return "{0}_{1}" -f $Mode.Trim().ToLowerInvariant(), $hash.Substring(0, 12)
}

$normalizedMode = $Mode.Trim().ToUpperInvariant()
$timestamp = Get-IsoUtcNow
$runKey = Get-DeterministicRunKey -Mode $Mode -BaseUrl $BaseUrl
$outputRoot = Join-Path $PSScriptRoot (Join-Path 'output' $runKey)
$runReportPath = Join-Path $outputRoot 'RUN_REPORT.json'
$failurePath = Join-Path $outputRoot 'failure_summary.json'

$capabilityStatus = [ordered]@{
    link = 'ACTIVE'
    capture = 'NOT_IMPLEMENTED'
    routes = 'NOT_IMPLEMENTED'
    page_quality = 'NOT_IMPLEMENTED'
    decision = 'NOT_IMPLEMENTED'
}

$learningBacklog = @(
    'Implement LINK crawler coverage depth controls.',
    'Define route normalization contract for LINK mode outputs.',
    'Design page quality scoring rubric for future sprint.',
    'Add decision synthesis contract after quality signals stabilize.'
)

$report = [ordered]@{
    mode = $normalizedMode
    base_url = $BaseUrl
    status = 'PASS'
    run_id = $runKey
    output_folder = $outputRoot
    timestamp_utc = $timestamp
    capability_status = $capabilityStatus
    learning_backlog = $learningBacklog
    linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath }
    )
    summary = 'LINK mode scaffold executed. Non-LINK capabilities are marked NOT_IMPLEMENTED for Sprint A.'
    next_step = 'Implement deterministic LINK traversal artifact generation in Sprint B.'
}

$shouldFail = $false
$errorCode = ''
$errorMessage = ''

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $shouldFail = $true
    $errorCode = 'INVALID_BASE_URL'
    $errorMessage = 'BaseUrl must be non-empty.'
}

if ($normalizedMode -ne 'LINK') {
    $shouldFail = $true
    $errorCode = 'UNSUPPORTED_MODE'
    $errorMessage = "Only MODE=LINK is supported. Received '$Mode'."
}

if ($shouldFail) {
    $report.status = 'FAIL'
    $report.summary = "Run failed: $errorCode"
    $report.next_step = $errorMessage
    $report.linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'failure_summary'; path = $failurePath }
    )
}

Write-JsonFile -Path $runReportPath -Data $report

if ($shouldFail) {
    $failure = [ordered]@{
        mode = $normalizedMode
        base_url = $BaseUrl
        status = 'FAIL'
        error_code = $errorCode
        message = $errorMessage
        timestamp_utc = Get-IsoUtcNow
        run_report_path = $runReportPath
    }
    Write-JsonFile -Path $failurePath -Data $failure
    exit 1
}

exit 0
