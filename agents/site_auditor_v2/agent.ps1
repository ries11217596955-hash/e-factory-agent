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

function Get-ShallowRoutes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootUrl,
        [int]$MaxRoutes = 10
    )

    $rootUri = [Uri]$RootUrl
    $rootResponse = Invoke-WebRequest -Uri $RootUrl -Method Get -MaximumRedirection 5
    $rootHtml = [string]$rootResponse.Content
    $hrefMatches = [regex]::Matches($rootHtml, '(?is)<a\b[^>]*href\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')
    $uniqueUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $routeUrls = [System.Collections.Generic.List[string]]::new()

    foreach ($match in $hrefMatches) {
        $rawHref = if (-not [string]::IsNullOrWhiteSpace($match.Groups[2].Value)) {
            $match.Groups[2].Value
        }
        elseif (-not [string]::IsNullOrWhiteSpace($match.Groups[3].Value)) {
            $match.Groups[3].Value
        }
        else {
            $match.Groups[4].Value
        }

        if ([string]::IsNullOrWhiteSpace($rawHref)) {
            continue
        }

        $trimmedHref = $rawHref.Trim()
        if ($trimmedHref.StartsWith('#')) {
            continue
        }

        try {
            $resolvedUri = [Uri]::new($rootUri, $trimmedHref)
        }
        catch {
            continue
        }

        if ($resolvedUri.Scheme -notin @('http', 'https')) {
            continue
        }

        if ($resolvedUri.Host -ne $rootUri.Host) {
            continue
        }

        $sanitizedUrl = $resolvedUri.GetLeftPart([System.UriPartial]::Path)
        if (-not [string]::IsNullOrWhiteSpace($resolvedUri.Query)) {
            $sanitizedUrl = "{0}{1}" -f $sanitizedUrl, $resolvedUri.Query
        }

        if ($uniqueUrls.Add($sanitizedUrl)) {
            $routeUrls.Add($sanitizedUrl)
        }

        if ($routeUrls.Count -ge $MaxRoutes) {
            break
        }
    }

    $routes = [System.Collections.Generic.List[object]]::new()
    foreach ($routeUrl in $routeUrls) {
        try {
            $routeResponse = Invoke-WebRequest -Uri $routeUrl -Method Get -MaximumRedirection 5
            $routeHtml = [string]$routeResponse.Content
            $routeTitleMatch = [regex]::Match($routeHtml, '(?is)<title[^>]*>(.*?)</title>')
            $routeTitle = if ($routeTitleMatch.Success) {
                [System.Net.WebUtility]::HtmlDecode($routeTitleMatch.Groups[1].Value).Trim()
            }
            else {
                ''
            }

            $routes.Add([ordered]@{
                    url = $routeUrl
                    status_code = [int]$routeResponse.StatusCode
                    title = $routeTitle
                    html_length = [int]$routeHtml.Length
                })
        }
        catch {
            $routes.Add([ordered]@{
                    url = $routeUrl
                    status_code = -1
                    title = ''
                    html_length = 0
                })
        }
    }

    return [ordered]@{
        root = $RootUrl
        routes = $routes
    }
}

$normalizedMode = $Mode.Trim().ToUpperInvariant()
$timestamp = Get-IsoUtcNow
$runKey = Get-DeterministicRunKey -Mode $Mode -BaseUrl $BaseUrl
$outputRoot = Join-Path $PSScriptRoot (Join-Path 'output' $runKey)
$runReportPath = Join-Path $outputRoot 'RUN_REPORT.json'
$linkSummaryPath = Join-Path $outputRoot 'LINK_SUMMARY.json'
$routesSummaryPath = Join-Path $outputRoot 'ROUTES_SUMMARY.json'
$auditSummaryPath = Join-Path $outputRoot 'AUDIT_SUMMARY.json'
$actionSummaryPath = Join-Path $outputRoot 'ACTION_SUMMARY.json'
$actionReportPath = Join-Path $outputRoot 'ACTION_REPORT.txt'
$failurePath = Join-Path $outputRoot 'failure_summary.json'
$deterministicRunReportPath = Join-Path $PSScriptRoot 'RUN_REPORT.json'
$deterministicLinkSummaryPath = Join-Path $PSScriptRoot 'LINK_SUMMARY.json'
$deterministicRoutesSummaryPath = Join-Path $PSScriptRoot 'ROUTES_SUMMARY.json'
$deterministicAuditSummaryPath = Join-Path $PSScriptRoot 'AUDIT_SUMMARY.json'
$deterministicActionSummaryPath = Join-Path $PSScriptRoot 'ACTION_SUMMARY.json'
$deterministicActionReportPath = Join-Path $PSScriptRoot 'ACTION_REPORT.txt'
$deterministicFailurePath = Join-Path $PSScriptRoot 'failure_summary.json'

$capabilityStatus = [ordered]@{
    link = 'ACTIVE'
    capture = 'NOT_IMPLEMENTED'
    routes = 'ACTIVE'
    page_quality = 'NOT_IMPLEMENTED'
    decision = 'NOT_IMPLEMENTED'
}

$learningBacklog = @(
    'Implement LINK crawler coverage depth controls.',
    'Define route normalization contract for LINK mode outputs.',
    'Design page quality scoring rubric for future sprint.',
    'Add decision synthesis contract after quality signals stabilize.'
)

$producedArtifacts = [System.Collections.Generic.List[string]]::new()
$null = $producedArtifacts.Add('RUN_REPORT.json')

$report = [ordered]@{
    mode = $normalizedMode
    base_url = $BaseUrl
    status = 'PASS'
    run_id = $runKey
    output_folder = $outputRoot
    timestamp_utc = $timestamp
    capability_status = $capabilityStatus
    learning_backlog = $learningBacklog
    produced_artifacts = @($producedArtifacts)
    linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'link_summary'; path = $linkSummaryPath },
        [ordered]@{ name = 'routes_summary'; path = $routesSummaryPath },
        [ordered]@{ name = 'audit_summary'; path = $auditSummaryPath },
        [ordered]@{ name = 'action_summary'; path = $actionSummaryPath },
        [ordered]@{ name = 'action_report'; path = $actionReportPath }
    )
    truth_files = [ordered]@{
        primary = @(
            'RUN_REPORT.json',
            'LINK_SUMMARY.json',
            'ROUTES_SUMMARY.json',
            'AUDIT_SUMMARY.json',
            'ACTION_SUMMARY.json',
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
        'ROUTES_SUMMARY.json',
        'AUDIT_SUMMARY.json',
        'ACTION_SUMMARY.json',
        'failure_summary.json',
        'agents/site_auditor_v2/agent.ps1',
        '.github/workflows/site-auditor-v2-link.yml'
    )
    problem_targets = @()
    operator_handoff = [ordered]@{
        reader_role = 'ChatGPT decision/orchestration layer'
        must_do_before_next_task = @(
            'open problem_targets pages',
            'inspect their structure',
            'compare thin vs ok pages'
        )
        what_to_inspect_next = @(
            'open problem_targets pages',
            'inspect their structure',
            'compare thin vs ok pages'
        )
        forbidden_moves = @(
            'do not guess parameter names',
            'do not generate task without reading truth_files',
            'do not patch unrelated files'
        )
        if_missing_artifact = 'Request exact missing file; do not proceed'
        primary_problem = 'structure unclear'
        focus_files = @(
            'ROUTES_SUMMARY.json',
            'AUDIT_SUMMARY.json'
        )
        next_task_shape = 'refine actions only'
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
    $report.produced_artifacts = @($producedArtifacts)
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
        $null = $producedArtifacts.Add('LINK_SUMMARY.json')

        $routesSummary = Get-ShallowRoutes -RootUrl $BaseUrl -MaxRoutes 10
        foreach ($route in $routesSummary.routes) {
            $classification = if ($route.status_code -ne 200) {
                'broken'
            }
            elseif ($route.html_length -lt 1500) {
                'thin'
            }
            else {
                'ok'
            }
            $route.classification = $classification
        }
        Write-JsonFile -Path $routesSummaryPath -Data $routesSummary
        Copy-Item -LiteralPath $routesSummaryPath -Destination $deterministicRoutesSummaryPath -Force
        $null = $producedArtifacts.Add('ROUTES_SUMMARY.json')

        $brokenTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'broken' } |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'broken'
                    reason = 'status_code not 200'
                    action = 'fix or remove page'
                }
            }
        )
        $thinTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'thin' } |
            Sort-Object html_length, url |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'thin'
                    reason = 'low html_length'
                    action = 'expand content'
                }
            }
        )
        $problemTargets = @($brokenTargets + $thinTargets)
        $report.problem_targets = $problemTargets

        $actionSummary = @(
            $problemTargets |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    issue = $_.classification
                    action = $_.action
                }
            }
        )
        Write-JsonFile -Path $actionSummaryPath -Data $actionSummary
        Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
        $null = $producedArtifacts.Add('ACTION_SUMMARY.json')

        $okCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'ok' }).Count
        $thinCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'thin' }).Count
        $brokenCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'broken' }).Count
        $auditSummary = [ordered]@{
            total = [int]@($routesSummary.routes).Count
            ok = [int]$okCount
            thin = [int]$thinCount
            broken = [int]$brokenCount
        }
        Write-JsonFile -Path $auditSummaryPath -Data $auditSummary
        Copy-Item -LiteralPath $auditSummaryPath -Destination $deterministicAuditSummaryPath -Force
        $null = $producedArtifacts.Add('AUDIT_SUMMARY.json')

        $actionReportLines = [System.Collections.Generic.List[string]]::new()
        $actionReportLines.Add("Site: $BaseUrl")
        $actionReportLines.Add("Total pages checked: $($auditSummary.total)")
        $actionReportLines.Add("Thin: $($auditSummary.thin)")
        $actionReportLines.Add("Broken: $($auditSummary.broken)")

        foreach ($target in $problemTargets) {
            $actionReportLines.Add('')
            $actionReportLines.Add("URL: $($target.url)")
            $actionReportLines.Add("Issue: $($target.classification)")
            $actionReportLines.Add("Action: $($target.action)")
        }

        $actionReportContent = [string]::Join([Environment]::NewLine, $actionReportLines)
        [System.IO.File]::WriteAllText($actionReportPath, $actionReportContent)
        Copy-Item -LiteralPath $actionReportPath -Destination $deterministicActionReportPath -Force
        $null = $producedArtifacts.Add('ACTION_REPORT.txt')

        if ($problemTargets.Count -eq 0) {
            $report.operator_handoff.must_do_before_next_task = @(
                'review ROUTES_SUMMARY.json route coverage',
                'confirm AUDIT_SUMMARY.json counts',
                'verify ACTION_SUMMARY.json is empty'
            )
            $report.operator_handoff.what_to_inspect_next = @(
                'ROUTES_SUMMARY.json',
                'AUDIT_SUMMARY.json',
                'ACTION_SUMMARY.json'
            )
        }

        $report.operator_handoff.next_task_shape = 'refine actions only'
        $report.produced_artifacts = @($producedArtifacts)
    }
    catch {
        $shouldFail = $true
        $errorCode = 'LINK_FETCH_FAILED'
        $errorMessage = $_.Exception.Message
        $report.status = 'FAIL'
        $report.summary = "Run failed: $errorCode"
        $report.next_step = $errorMessage
        $report.produced_artifacts = @($producedArtifacts)
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
    $report.produced_artifacts = @($producedArtifacts + 'failure_summary.json')
    Write-JsonFile -Path $runReportPath -Data $report
    Copy-Item -LiteralPath $runReportPath -Destination $deterministicRunReportPath -Force
    exit 1
}

exit 0
