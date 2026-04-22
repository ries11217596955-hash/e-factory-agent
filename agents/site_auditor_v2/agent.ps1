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

function Get-LinkSignals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $response = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 5
    $statusCode = [int]$response.StatusCode
    $html = [string]$response.Content

    $titleMatch = [regex]::Match($html, '(?is)<title[^>]*>(.*?)</title>')
    $title = if ($titleMatch.Success) {
        [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value).Trim()
    }
    else {
        ''
    }

    $linkMatches = [regex]::Matches($html, '(?is)<a\b[^>]*href\s*=')
    $linkCount = [int]$linkMatches.Count
    $htmlLength = [int]$html.Length
    $isThin = (($htmlLength -lt 500) -or ([string]::IsNullOrWhiteSpace($title)) -or ($linkCount -le 1))

    return [ordered]@{
        url = $Url
        status_code = $statusCode
        title = $title
        html_length = $htmlLength
        link_count = $linkCount
        is_thin = $isThin
    }
}

$normalizedMode = $Mode.Trim().ToUpperInvariant()
$timestamp = Get-IsoUtcNow
$runKey = Get-DeterministicRunKey -Mode $Mode -BaseUrl $BaseUrl
$outputRoot = Join-Path $PSScriptRoot (Join-Path 'output' $runKey)
$runReportPath = Join-Path $outputRoot 'RUN_REPORT.json'
$linkSummaryPath = Join-Path $outputRoot 'LINK_SUMMARY.json'
$failurePath = Join-Path $outputRoot 'failure_summary.json'
$deterministicRunReportPath = Join-Path $PSScriptRoot 'RUN_REPORT.json'
$deterministicLinkSummaryPath = Join-Path $PSScriptRoot 'LINK_SUMMARY.json'
$deterministicFailurePath = Join-Path $PSScriptRoot 'failure_summary.json'

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
    produced_artifacts = @(
        'RUN_REPORT.json',
        'LINK_SUMMARY.json'
    )
    linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'link_summary'; path = $linkSummaryPath }
    )
    truth_files = [ordered]@{
        primary = @(
            'RUN_REPORT.json',
            'LINK_SUMMARY.json',
            'failure_summary.json'
        )
        context = @(
            'agents/site_auditor_v2/agent.ps1',
            '.github/workflows/site-auditor-v2-link.yml'
        )
    }
    read_order = @(
        'RUN_REPORT.json',
        'LINK_SUMMARY.json',
        'failure_summary.json',
        'agents/site_auditor_v2/agent.ps1',
        '.github/workflows/site-auditor-v2-link.yml'
    )
    operator_handoff = [ordered]@{
        reader_role = 'ChatGPT decision/orchestration layer'
        must_do_before_next_task = @(
            'open agent param block',
            'verify workflow parameter mapping',
            'verify actual output path'
        )
        forbidden_moves = @(
            'do not guess parameter names',
            'do not generate task without reading truth_files',
            'do not patch unrelated files'
        )
        if_missing_artifact = 'Request exact missing file; do not proceed'
        next_task_shape = 'expand LINK coverage'
        scope_constraint = 'expand LINK capture only'
    }
    summary = 'LINK mode executes a live page fetch and writes base LINK signals to artifacts.'
    next_step = 'Expand LINK capture only.'
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
else {
    try {
        $linkSummary = Get-LinkSignals -Url $BaseUrl
        Write-JsonFile -Path $linkSummaryPath -Data $linkSummary
        Copy-Item -LiteralPath $linkSummaryPath -Destination $deterministicLinkSummaryPath -Force
    }
    catch {
        $shouldFail = $true
        $errorCode = 'LINK_FETCH_FAILED'
        $errorMessage = $_.Exception.Message
        $report.status = 'FAIL'
        $report.summary = "Run failed: $errorCode"
        $report.next_step = $errorMessage
        $report.linked_artifacts = @(
            [ordered]@{ name = 'run_report'; path = $runReportPath },
            [ordered]@{ name = 'failure_summary'; path = $failurePath }
        )
    }
}

Write-JsonFile -Path $runReportPath -Data $report
Copy-Item -LiteralPath $runReportPath -Destination $deterministicRunReportPath -Force

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
    Copy-Item -LiteralPath $failurePath -Destination $deterministicFailurePath -Force
    exit 1
}

exit 0
