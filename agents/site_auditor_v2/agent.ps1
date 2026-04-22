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
    $uniqueRouteKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $routeUrls = [System.Collections.Generic.List[object]]::new()
    $normalizationFailed = $false
    $normalizationErrors = [System.Collections.Generic.List[string]]::new()

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

        $normalizationResult = Get-NormalizedRouteResult -Url $resolvedUri.AbsoluteUri
        if ($normalizationResult.status -eq 'failed') {
            $normalizationFailed = $true
            $normalizationErrors.Add("route=$($resolvedUri.AbsoluteUri); reason=$($normalizationResult.error)")
        }

        if ($uniqueRouteKeys.Add($normalizationResult.normalized_route)) {
            $routeUrls.Add($normalizationResult)
        }

        if ($routeUrls.Count -ge $MaxRoutes) {
            break
        }
    }

    $routes = [System.Collections.Generic.List[object]]::new()
    foreach ($routeTarget in $routeUrls) {
        try {
            $routeResponse = Invoke-WebRequest -Uri $routeTarget.url -Method Get -MaximumRedirection 5
            $routeHtml = [string]$routeResponse.Content
            $routeTitleMatch = [regex]::Match($routeHtml, '(?is)<title[^>]*>(.*?)</title>')
            $routeTitle = if ($routeTitleMatch.Success) {
                [System.Net.WebUtility]::HtmlDecode($routeTitleMatch.Groups[1].Value).Trim()
            }
            else {
                ''
            }

            $routes.Add([ordered]@{
                    url = $routeTarget.url
                    normalized_route = $routeTarget.normalized_route
                    status_code = [int]$routeResponse.StatusCode
                    title = $routeTitle
                    html_length = [int]$routeHtml.Length
                })
        }
        catch {
            $routes.Add([ordered]@{
                    url = $routeTarget.url
                    normalized_route = $routeTarget.normalized_route
                    status_code = -1
                    title = ''
                    html_length = 0
                })
        }
    }

    return [ordered]@{
        root = $RootUrl
        routes = $routes
        route_normalization = if ($normalizationFailed) { 'failed' } else { 'ok' }
        route_normalization_errors = @($normalizationErrors)
    }
}

function Get-NormalizedRouteResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $uri = [Uri]$Url
        $path = [string]$uri.AbsolutePath
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = '/'
        }

        $normalizedPath = $path.Trim()
        $normalizedPath = $normalizedPath.ToLowerInvariant()
        $normalizedPath = [regex]::Replace($normalizedPath, '/index\.html$', '/')

        if (($normalizedPath.Length -gt 1) -and $normalizedPath.EndsWith('/')) {
            $normalizedPath = $normalizedPath.TrimEnd('/')
        }
        if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
            $normalizedPath = '/'
        }
        if (-not $normalizedPath.StartsWith('/')) {
            $normalizedPath = "/$normalizedPath"
        }

        $query = [string]$uri.Query
        $normalizedRoute = if ([string]::IsNullOrWhiteSpace($query)) {
            $normalizedPath
        }
        else {
            "{0}{1}" -f $normalizedPath, $query
        }

        $builder = [UriBuilder]::new($uri)
        $builder.Path = $normalizedPath
        $builder.Query = $query.TrimStart('?')
        $builder.Fragment = ''
        $normalizedUrl = $builder.Uri.AbsoluteUri

        return [ordered]@{
            status = 'ok'
            url = $normalizedUrl
            normalized_route = $normalizedRoute
            source_url = $Url
            error = ''
        }
    }
    catch {
        return [ordered]@{
            status = 'failed'
            url = $Url
            normalized_route = $Url
            source_url = $Url
            error = [string]$_.Exception.Message
        }
    }
}

function Get-CanonicalRouteKeyResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteValue,
        [string]$BaseUrl = ''
    )

    $value = [string]$RouteValue
    if ([string]::IsNullOrWhiteSpace($value)) {
        return [ordered]@{
            status = 'failed'
            canonical_route = ''
            source_value = $RouteValue
            error = 'route value is empty'
        }
    }

    $trimmedValue = $value.Trim()
    $candidateUrl = $trimmedValue

    if (-not ($trimmedValue -match '^[a-z][a-z0-9+\-.]*://')) {
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
            return [ordered]@{
                status = 'failed'
                canonical_route = ''
                source_value = $RouteValue
                error = 'base URL is required to normalize relative route values'
            }
        }

        try {
            $candidateUrl = [Uri]::new([Uri]$BaseUrl, $trimmedValue).AbsoluteUri
        }
        catch {
            return [ordered]@{
                status = 'failed'
                canonical_route = ''
                source_value = $RouteValue
                error = [string]$_.Exception.Message
            }
        }
    }

    $normalizedResult = Get-NormalizedRouteResult -Url $candidateUrl
    if ($normalizedResult.status -eq 'failed') {
        return [ordered]@{
            status = 'failed'
            canonical_route = ''
            source_value = $RouteValue
            error = [string]$normalizedResult.error
        }
    }

    return [ordered]@{
        status = 'ok'
        canonical_route = [string]$normalizedResult.normalized_route
        source_value = $RouteValue
        error = ''
    }
}

function Get-VisualTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [int]$MaxPages = 5
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    $seenRoutes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $tierOne = [System.Collections.Generic.List[object]]::new()
    $tierTwo = [System.Collections.Generic.List[object]]::new()
    $decisionKeywords = @('tool', 'best', 'how', 'guide')
    $lowValueKeywords = @('tag', 'category', 'archive', 'page', 'feed')

    function Get-RouteTypeAndPriority {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RouteKey
        )

        try {
            $routeLower = $RouteKey.ToLowerInvariant()
            if ($routeLower -eq '/') {
                return [ordered]@{ type = 'ROOT'; priority = 1 }
            }

            if ($routeLower -match '(^|/)feed(/|$|\?)' -or $routeLower -match '(^|/)rss(/|$|\?)' -or $routeLower -match '(^|/)page/\d+(/|$|\?)') {
                return [ordered]@{ type = 'LOW_VALUE'; priority = 3; hard_exclude = $true }
            }

            foreach ($keyword in $decisionKeywords) {
                if ($routeLower.Contains($keyword)) {
                    return [ordered]@{ type = 'DECISION'; priority = 1 }
                }
            }

            foreach ($keyword in $lowValueKeywords) {
                if ($routeLower.Contains($keyword)) {
                    return [ordered]@{ type = 'LOW_VALUE'; priority = 3 }
                }
            }

            return [ordered]@{ type = 'CONTENT'; priority = 2 }
        }
        catch {
            return [ordered]@{ type = 'CONTENT'; priority = 2 }
        }
    }

    function Get-SafeRouteClassification {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RouteKey
        )

        $defaultClassification = [ordered]@{ type = 'CONTENT'; priority = 2 }

        try {
            $classification = Get-RouteTypeAndPriority -RouteKey $RouteKey
            if (-not $classification) {
                return $defaultClassification
            }

            $classificationType = if ($classification.PSObject.Properties['type']) {
                [string]$classification.type
            }
            else {
                'CONTENT'
            }

            $classificationPriority = if ($classification.PSObject.Properties['priority'] -and $classification.priority -as [int]) {
                [int]$classification.priority
            }
            else {
                switch ($classificationType) {
                    'ROOT' { 1 }
                    'DECISION' { 1 }
                    'LOW_VALUE' { 3 }
                    default { 2 }
                }
            }

            $safeClassification = [ordered]@{
                type = $classificationType
                priority = $classificationPriority
            }

            if ($classification.PSObject.Properties['hard_exclude']) {
                $safeClassification.hard_exclude = [bool]$classification.hard_exclude
            }

            return $safeClassification
        }
        catch {
            return $defaultClassification
        }
    }

    $baseUri = [Uri]$BaseUrl
    $rootBuilder = [UriBuilder]::new($baseUri)
    $rootBuilder.Path = '/'
    $rootBuilder.Query = ''
    $rootBuilder.Fragment = ''
    $baseNormalized = Get-NormalizedRouteResult -Url $rootBuilder.Uri.AbsoluteUri
    if ($seenRoutes.Add($baseNormalized.normalized_route)) {
        $baseClassification = Get-SafeRouteClassification -RouteKey $baseNormalized.normalized_route
        if (-not $baseClassification.PSObject.Properties['hard_exclude'] -or -not [bool]$baseClassification.hard_exclude) {
            $baseSelectionReason = switch ([string]$baseClassification.type) {
                'ROOT' { 'tier_1_root_page' }
                'DECISION' { 'tier_1_decision_page' }
                'CONTENT' { 'tier_2_content_page' }
                default { 'tier_2_content_page' }
            }
            $tierOne.Add([ordered]@{
                    route = $baseNormalized.normalized_route
                    type = [string]$baseClassification.type
                    priority = [int]$baseClassification.priority
                    url = $baseNormalized.url
                    selection_reason = $baseSelectionReason
                })
        }
    }

    foreach ($route in $RoutesSummary.routes) {
        if ($route.status_code -ne 200) {
            continue
        }

        $routeKey = if ($route.PSObject.Properties['normalized_route']) {
            [string]$route.normalized_route
        }
        else {
            [string]$route.url
        }

        if (-not $seenRoutes.Add($routeKey)) {
            continue
        }

        $classification = Get-SafeRouteClassification -RouteKey $routeKey
        if ($classification.PSObject.Properties['hard_exclude'] -and [bool]$classification.hard_exclude) {
            continue
        }
        if ($classification.type -eq 'LOW_VALUE') {
            continue
        }

        $selectionReason = switch ([string]$classification.type) {
            'ROOT' { 'tier_1_root_page' }
            'DECISION' { 'tier_1_decision_page' }
            'CONTENT' { 'tier_2_content_page' }
            default { 'tier_2_content_page' }
        }

        $target = [ordered]@{
            route = $routeKey
            type = [string]$classification.type
            priority = [int]$classification.priority
            url = [string]$route.url
            selection_reason = $selectionReason
        }

        if ($classification.priority -eq 1) {
            $tierOne.Add($target)
        }
        else {
            $tierTwo.Add($target)
        }
    }

    foreach ($target in $tierOne) {
        if ($selected.Count -ge $MaxPages) {
            break
        }
        $selected.Add($target)
    }
    foreach ($target in $tierTwo) {
        if ($selected.Count -ge $MaxPages) {
            break
        }
        $selected.Add($target)
    }

    $allRankedTargets = @($tierOne + $tierTwo)
    $overflow = @(
        $allRankedTargets |
        Select-Object -Skip $selected.Count |
        ForEach-Object {
            [ordered]@{
                route = [string]$_.route
                type = [string]$_.type
                priority = [int]$_.priority
                selection_reason = [string]$_.selection_reason
                exclusion_reason = 'over_max_routes_tiered_priority_cutoff'
            }
        }
    )

    return [ordered]@{
        selected_routes = @($selected)
        overflow_routes = @($overflow)
        selection_strategy = 'tiered_priority'
    }
}

function Invoke-VisualCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Pages,
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$ScreenshotsPath
    )

    Ensure-Directory -Path $ScreenshotsPath
    $payloadPages = @(
        for ($i = 0; $i -lt $Pages.Count; $i++) {
            [ordered]@{
                index = ($i + 1)
                url = $Pages[$i]
            }
        }
    )
    $payload = [ordered]@{
        pages = $payloadPages
        screenshots_dir = $ScreenshotsPath
        viewport = [ordered]@{
            width = 1366
            height = 768
        }
    }
    Write-JsonFile -Path $InputPath -Data $payload

    & node $ToolPath $InputPath $ManifestPath
    return $LASTEXITCODE
}

function Invoke-EvidenceReconciliation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$ScreenshotsPath,
        [Parameter(Mandatory = $true)]
        [int]$RunReportPagesAttempted,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesAttempted,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesSuccess,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesFailed
    )

    $sizeThresholdBytes = 10000
    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $manifestPages = @($manifestRaw.pages)
    $captures = @(
        $manifestPages |
        ForEach-Object { @($_.captures) }
    )

    $pngFiles = if (Test-Path -LiteralPath $ScreenshotsPath) {
        @(Get-ChildItem -LiteralPath $ScreenshotsPath -File -Filter '*.png')
    }
    else {
        @()
    }

    $issues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $validCount = 0
    $invalidCount = 0
    $checksCompleted = $true
    $diagnostics = [System.Collections.Generic.List[string]]::new()

    foreach ($capture in $captures) {
        $relativeFile = [string]$capture.file
        if ([string]::IsNullOrWhiteSpace($relativeFile)) {
            $invalidCount += 1
            $null = $issues.Add('manifest_mismatch')
            continue
        }

        $normalizedRelative = $relativeFile.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $expectedPath = Join-Path (Split-Path -Parent $ManifestPath) $normalizedRelative
        $fileStatus = 'ok'

        if (-not (Test-Path -LiteralPath $expectedPath)) {
            $fileStatus = 'missing_capture'
            $null = $issues.Add('missing_capture')
        }
        else {
            try {
                $actualSize = [int](Get-Item -LiteralPath $expectedPath).Length
                if ($actualSize -lt $sizeThresholdBytes) {
                    $fileStatus = 'empty_capture'
                    $null = $issues.Add('empty_capture')
                }
                if ([int]$capture.size_bytes -ne $actualSize) {
                    $null = $issues.Add('size_mismatch')
                }
            }
            catch {
                $checksCompleted = $false
                $fileStatus = 'reconciliation_error'
                $null = $issues.Add('reconciliation_error')
                $diagnostics.Add($_.Exception.Message)
            }
        }

        if ($fileStatus -eq 'ok') {
            $validCount += 1
        }
        else {
            $invalidCount += 1
        }
    }

    $manifestCaptureCount = [int]$captures.Count
    $actualCaptureCount = [int]$pngFiles.Count
    if ($manifestCaptureCount -ne $actualCaptureCount) {
        $null = $issues.Add('manifest_mismatch')
    }

    $manifestPageCount = [int]$manifestPages.Count
    $pageRegex = '^page-(?<idx>\d{2})-'
    $actualUniquePageKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($png in $pngFiles) {
        $match = [regex]::Match($png.Name, $pageRegex)
        if ($match.Success) {
            $null = $actualUniquePageKeys.Add($match.Groups['idx'].Value)
        }
    }

    if (($RunReportPagesAttempted -ne $manifestPageCount) -or ($manifestPageCount -ne $actualUniquePageKeys.Count)) {
        $null = $issues.Add('RUN_REPORT_INCONSISTENT')
    }
    if (
        ($RunReportCapturesAttempted -ne $manifestCaptureCount) -or
        ($RunReportCapturesSuccess -ne $validCount) -or
        ($RunReportCapturesFailed -ne $invalidCount)
    ) {
        $null = $issues.Add('RUN_REPORT_COUNTER_MISMATCH')
    }

    $status = 'PASS'
    if ($validCount -eq 0 -and ($manifestCaptureCount -gt 0)) {
        $status = 'FAIL'
    }
    elseif ($invalidCount -gt 0 -or $issues.Count -gt 0) {
        $status = 'PARTIAL'
    }
    elseif ($manifestCaptureCount -eq 0) {
        $status = 'FAIL'
        $null = $issues.Add('no_captures')
    }

    if (-not $checksCompleted) {
        $status = 'FAIL'
        $null = $issues.Add('reconciliation_error')
    }

    if (
        ($issues.Contains('missing_capture')) -or
        ($issues.Contains('empty_capture')) -or
        ($issues.Contains('manifest_mismatch'))
    ) {
        if ($status -eq 'PASS') {
            $status = 'PARTIAL'
        }
    }

    return [ordered]@{
        status = $status
        files_checked = $manifestCaptureCount
        files_valid = [int]$validCount
        files_invalid = [int]$invalidCount
        issues = @($issues)
        manifest_pages = $manifestPageCount
        run_report_pages_attempted = $RunReportPagesAttempted
        actual_unique_pages = [int]$actualUniquePageKeys.Count
        diagnostics = @($diagnostics)
    }
}

$normalizedMode = $Mode.Trim().ToUpperInvariant()
$maxRoutes = 5
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
$visualManifestPath = Join-Path $outputRoot 'visual_manifest.json'
$visualInputPath = Join-Path $outputRoot 'visual_capture_input.json'
$screenshotsPath = Join-Path $outputRoot 'screenshots'
$deterministicRunReportPath = Join-Path $PSScriptRoot 'RUN_REPORT.json'
$deterministicLinkSummaryPath = Join-Path $PSScriptRoot 'LINK_SUMMARY.json'
$deterministicRoutesSummaryPath = Join-Path $PSScriptRoot 'ROUTES_SUMMARY.json'
$deterministicAuditSummaryPath = Join-Path $PSScriptRoot 'AUDIT_SUMMARY.json'
$deterministicActionSummaryPath = Join-Path $PSScriptRoot 'ACTION_SUMMARY.json'
$deterministicActionReportPath = Join-Path $PSScriptRoot 'ACTION_REPORT.txt'
$deterministicFailurePath = Join-Path $PSScriptRoot 'failure_summary.json'
$deterministicVisualManifestPath = Join-Path $PSScriptRoot 'visual_manifest.json'
$deterministicScreenshotsPath = Join-Path $PSScriptRoot 'screenshots'

$capabilityStatus = [ordered]@{
    link = 'ACTIVE'
    capture = 'ACTIVE'
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
$null = $producedArtifacts.Add('ACTION_REPORT.txt')

$notDoneYet = @(
    'Capture mode supports baseline screenshot evidence only (no interactions).',
    'Page-quality scoring is not implemented.',
    'Decision synthesis is not implemented.'
)

$cannotDoYet = @(
    'Cannot run repository-wide inspection in LINK mode.',
    'Cannot provide scoring decisions without page-quality module.'
)

$report = [ordered]@{
    mode = $normalizedMode
    base_url = $BaseUrl
    status = 'PASS'
    execution_status = 'SUCCESS'
    run_id = $runKey
    output_folder = $outputRoot
    timestamp_utc = $timestamp
    capability_status = $capabilityStatus
    learning_backlog = $learningBacklog
    execution_report = [ordered]@{
        final_outcome = 'PASS'
        status_detail = 'PASS'
        mode = $normalizedMode
    }
    not_done_yet = $notDoneYet
    cannot_do_yet = $cannotDoYet
    failure_or_limit_report = [ordered]@{
        kind = 'NONE'
        failure_summary = ''
        notes = @()
    }
    produced_artifacts = @($producedArtifacts)
    linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'link_summary'; path = $linkSummaryPath },
        [ordered]@{ name = 'routes_summary'; path = $routesSummaryPath },
        [ordered]@{ name = 'audit_summary'; path = $auditSummaryPath },
        [ordered]@{ name = 'action_summary'; path = $actionSummaryPath },
        [ordered]@{ name = 'action_report'; path = $actionReportPath },
        [ordered]@{ name = 'visual_manifest'; path = $visualManifestPath },
        [ordered]@{ name = 'screenshots'; path = $screenshotsPath }
    )
    truth_files = [ordered]@{
        primary = @(
            'RUN_REPORT.json',
            'LINK_SUMMARY.json',
            'ROUTES_SUMMARY.json',
            'AUDIT_SUMMARY.json',
            'ACTION_SUMMARY.json',
            'visual_manifest.json',
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
        'visual_manifest.json',
        'failure_summary.json',
        'agents/site_auditor_v2/agent.ps1',
        '.github/workflows/site-auditor-v2-link.yml'
    )
    problem_targets = @()
    operator_handoff = [ordered]@{
        reader_role = 'ChatGPT decision/orchestration layer'
        must_do_before_next_task = @(
            'read RUN_REPORT.json first',
            'confirm produced_artifacts are present',
            'inspect ACTION_REPORT.txt and ACTION_SUMMARY.json'
        )
        what_to_inspect_next = @(
            'RUN_REPORT.json',
            'ACTION_REPORT.txt',
            'ACTION_SUMMARY.json'
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
    summary = 'LINK mode executes live fetch, route checks, and screenshot evidence capture.'
    next_step = 'Stabilize screenshot evidence quality in LINK mode.'
    decision_allowed = $true
    reconciliation_enforced = $false
    route_normalization = 'ok'
}

$shouldFail = $false
$errorCode = ''
$errorMessage = ''
$reconciliationCompleted = $false
$counterMismatchDetected = $false

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
    $report.execution_status = 'FAILED'
    $report.summary = "Run failed: $errorCode"
    $report.next_step = $errorMessage
    $report.execution_report.final_outcome = 'FAIL'
    $report.execution_report.status_detail = 'FAIL'
    $report.failure_or_limit_report = [ordered]@{
        kind = 'FAILURE'
        failure_summary = 'failure_summary.json'
        notes = @($errorMessage)
    }
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
        $report.route_normalization = [string]$routesSummary.route_normalization
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
        $passStatus = if (($thinCount -gt 0) -or ($brokenCount -gt 0)) { 'PASS_WITH_LIMITS' } else { 'PASS' }
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

        $captureTargetPlan = Get-VisualTargets -BaseUrl $BaseUrl -RoutesSummary $routesSummary -MaxPages $maxRoutes
        $selectedRoutes = @($captureTargetPlan.selected_routes)
        $overflowRoutes = @($captureTargetPlan.overflow_routes)
        $selectedRoutesCount = [int]$selectedRoutes.Count
        $captureTargetUrls = @($selectedRoutes | ForEach-Object { [string]$_.url })
        $report.selected_routes = @(
            $selectedRoutes |
            ForEach-Object {
                [ordered]@{
                    route = [string]$_.route
                    type = [string]$_.type
                    priority = [int]$_.priority
                    selection_reason = [string]$_.selection_reason
                }
            }
        )
        $report.run_budget = [ordered]@{
            max_routes = [int]$maxRoutes
            selected_routes = [int]$selectedRoutesCount
            selection_strategy = [string]$captureTargetPlan.selection_strategy
            overflow_routes = [int]$overflowRoutes.Count
            overflow_route_details = @($overflowRoutes)
        }

        if ($selectedRoutesCount -gt $maxRoutes) {
            throw "run_budget_violation: selected_routes_exceeded_max_routes"
        }
        $captureToolPath = Join-Path $PSScriptRoot 'tools/capture_visuals.mjs'
        $captureExitCode = Invoke-VisualCapture -Pages $captureTargetUrls -ToolPath $captureToolPath -InputPath $visualInputPath -ManifestPath $visualManifestPath -ScreenshotsPath $screenshotsPath
        Copy-Item -LiteralPath $visualManifestPath -Destination $deterministicVisualManifestPath -Force
        Ensure-Directory -Path $deterministicScreenshotsPath
        Get-ChildItem -LiteralPath $deterministicScreenshotsPath -File -Filter '*.png' | Remove-Item -Force
        if (Test-Path -LiteralPath $screenshotsPath) {
            Get-ChildItem -LiteralPath $screenshotsPath -File -Filter '*.png' | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $deterministicScreenshotsPath $_.Name) -Force
                $null = $producedArtifacts.Add("screenshots/$($_.Name)")
            }
        }
        $null = $producedArtifacts.Add('visual_manifest.json')

        $visualManifest = Get-Content -LiteralPath $visualManifestPath -Raw | ConvertFrom-Json
        $captureStatus = [string]$visualManifest.status
        $manifestRequestedPages = [int]$visualManifest.requested_pages
        $manifestProcessedPages = [int]$visualManifest.processed_pages
        $manifestFailedPages = [int]$visualManifest.failed_pages
        $captureSummary = [ordered]@{
            status = $captureStatus
            requested_pages = $manifestRequestedPages
            processed_pages = $manifestProcessedPages
            failed_pages = $manifestFailedPages
            exit_code = [int]$captureExitCode
            counter_mismatch = $false
        }
        $report.capture_summary = $captureSummary
        $manifestPages = @($visualManifest.pages)

        $selectedRouteKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $routeNormalizationErrors = [System.Collections.Generic.List[object]]::new()
        foreach ($target in $selectedRoutes) {
            $selectedRouteValue = if (-not [string]::IsNullOrWhiteSpace([string]$target.route)) {
                [string]$target.route
            }
            else {
                [string]$target.url
            }

            $canonicalResult = Get-CanonicalRouteKeyResult -RouteValue $selectedRouteValue -BaseUrl $BaseUrl
            if ($canonicalResult.status -eq 'ok') {
                $null = $selectedRouteKeys.Add([string]$canonicalResult.canonical_route)
                continue
            }

            $routeNormalizationErrors.Add([ordered]@{
                    source = 'selected_route'
                    value = $selectedRouteValue
                    error = [string]$canonicalResult.error
                })
        }

        $manifestRouteKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($manifestPage in $manifestPages) {
            $manifestPageUrl = if ($manifestPage.PSObject.Properties['url']) {
                [string]$manifestPage.url
            }
            elseif ($manifestPage.PSObject.Properties['source_url']) {
                [string]$manifestPage.source_url
            }
            else {
                ''
            }
            if (-not [string]::IsNullOrWhiteSpace($manifestPageUrl)) {
                $canonicalResult = Get-CanonicalRouteKeyResult -RouteValue $manifestPageUrl -BaseUrl $BaseUrl
                if ($canonicalResult.status -eq 'ok') {
                    $null = $manifestRouteKeys.Add([string]$canonicalResult.canonical_route)
                }
                else {
                    $routeNormalizationErrors.Add([ordered]@{
                            source = 'manifest_route'
                            value = $manifestPageUrl
                            error = [string]$canonicalResult.error
                        })
                }
            }
        }

        $missingManifestRoutes = @($selectedRouteKeys | Where-Object { -not $manifestRouteKeys.Contains($_) })
        $extraManifestRoutes = @($manifestRouteKeys | Where-Object { -not $selectedRouteKeys.Contains($_) })
        $normalizationErrorDetected = ($routeNormalizationErrors.Count -gt 0)

        if ($normalizationErrorDetected -or $selectedRoutesCount -ne $manifestRequestedPages -or $manifestPages.Count -ne $selectedRoutesCount -or $missingManifestRoutes.Count -gt 0 -or $extraManifestRoutes.Count -gt 0) {
            $counterMismatchDetected = $true
            $report.capture_summary.counter_mismatch = $true
            if ($report.capture_summary.status -eq 'PASS') {
                $report.capture_summary.status = 'PARTIAL'
            }
            $report.capture_summary.counter_mismatch_details = [ordered]@{
                selected_routes = $selectedRoutesCount
                selected_route_keys = [int]$selectedRouteKeys.Count
                manifest_requested_pages = $manifestRequestedPages
                manifest_pages = [int]$manifestPages.Count
                manifest_route_keys = [int]$manifestRouteKeys.Count
                missing_routes = @($missingManifestRoutes)
                extra_routes = @($extraManifestRoutes)
                normalization_error = $normalizationErrorDetected
                normalization_errors = @($routeNormalizationErrors)
            }
        }

        $captures = @(
            $manifestPages |
            ForEach-Object { @($_.captures) }
        )
        $capturesAttempted = [int]$captures.Count
        $capturesSuccess = [int]@($captures | Where-Object { $_.status -eq 'ok' }).Count
        $capturesFailed = [int]($capturesAttempted - $capturesSuccess)
        $pagesAttempted = [int]$selectedRoutesCount
        $pagesProcessed = [int]$manifestProcessedPages
        $pagesFailed = [int]$manifestFailedPages
        $pagesSuccess = [int]@(
            $manifestPages |
            Where-Object { @($_.captures | Where-Object { $_.status -eq 'ok' }).Count -gt 0 }
        ).Count
        $failTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($capture in ($captures | Where-Object { $_.status -ne 'ok' })) {
            if (-not [string]::IsNullOrWhiteSpace([string]$capture.status)) {
                $null = $failTypes.Add([string]$capture.status)
            }
        }
        foreach ($manifestPage in ($manifestPages | Where-Object { $_.status -eq 'FAIL' })) {
            $null = $failTypes.Add('render_fail')
        }

        $captureReportStatus = 'PASS'
        if ($pagesSuccess -eq 0) {
            $captureReportStatus = 'FAIL'
        }
        elseif ($capturesFailed -gt 0) {
            $captureReportStatus = 'PARTIAL'
        }

        $report.capture_report = [ordered]@{
            status = $captureReportStatus
            pages_attempted = $pagesAttempted
            pages_processed = $pagesProcessed
            pages_success = $pagesSuccess
            pages_failed = $pagesFailed
            captures_attempted = $capturesAttempted
            captures_success = $capturesSuccess
            captures_failed = $capturesFailed
            fail_types = @($failTypes)
            counter_mismatch = [bool]$counterMismatchDetected
        }

        try {
            $reconciliation = Invoke-EvidenceReconciliation -ManifestPath $visualManifestPath -ScreenshotsPath $screenshotsPath -RunReportPagesAttempted $pagesAttempted -RunReportCapturesAttempted $capturesAttempted -RunReportCapturesSuccess $capturesSuccess -RunReportCapturesFailed $capturesFailed
            $report.evidence_reconciliation = [ordered]@{
                status = $reconciliation.status
                files_checked = $reconciliation.files_checked
                files_valid = $reconciliation.files_valid
                files_invalid = $reconciliation.files_invalid
                issues = @($reconciliation.issues)
            }
            $report.reconciliation_enforced = $true

            if (@('PASS', 'PARTIAL', 'FAIL') -notcontains [string]$reconciliation.status) {
                throw "Reconciliation returned unsupported status '$([string]$reconciliation.status)'."
            }

            $reconciliationCompleted = $true
            $report.capture_report.status = [string]$reconciliation.status

            $visualEvidence = switch ([string]$reconciliation.status) {
                'PASS' { 'trusted' }
                'PARTIAL' { 'partial' }
                default { 'invalid' }
            }
            $report.trust_boundary = [ordered]@{
                visual_evidence = $visualEvidence
                decision_allowed = $false
                reason = 'reconciliation_result'
            }

            if ($reconciliation.status -eq 'PARTIAL') {
                $report.trust_boundary.visual_truth = 'partial'
                $report.trust_boundary.impact = 'downstream analysis limited'
            }
        }
        catch {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.decision_disabled = $true
            $report.decision_allowed = $false
            $report.reconciliation_enforced = $true
            $report.capture_report.status = 'FAIL'
            $report.evidence_reconciliation = [ordered]@{
                status = 'FAIL'
                files_checked = 0
                files_valid = 0
                files_invalid = 0
                issues = @('reconciliation_error')
                diagnostics = @([string]$_.Exception.Message)
            }
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @('Evidence reconciliation failed.', [string]$_.Exception.Message)
            }
            $shouldFail = $true
            $errorCode = 'EVIDENCE_RECONCILIATION_FAILED'
            $errorMessage = $_.Exception.Message
        }

        if (-not $reconciliationCompleted) {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.decision_disabled = $true
            $report.decision_allowed = $false
            $report.trust_boundary = [ordered]@{
                visual_evidence = 'invalid'
                decision_allowed = $false
                reason = 'reconciliation_result'
            }
            $shouldFail = $true
            if ([string]::IsNullOrWhiteSpace($errorCode)) {
                $errorCode = 'EVIDENCE_RECONCILIATION_NOT_EXECUTED'
                $errorMessage = 'Evidence reconciliation did not execute.'
            }
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @($errorMessage)
            }
        }

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
        else {
            $report.operator_handoff.must_do_before_next_task = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
            $report.operator_handoff.what_to_inspect_next = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
        }

        $report.operator_handoff.next_task_shape = 'refine actions only'
        $report.execution_report.final_outcome = 'PASS'
        $limitNotes = [System.Collections.Generic.List[string]]::new()
        if ($thinCount -gt 0) { $limitNotes.Add("thin_pages=$thinCount") }
        if ($brokenCount -gt 0) { $limitNotes.Add("broken_pages=$brokenCount") }
        if ($report.capture_report.status -eq 'FAIL') {
            $limitNotes.Add('capture_status=FAIL')
            $limitNotes.Add('incomplete visual coverage: no page had a valid screenshot capture')
        }
        elseif ($report.capture_report.status -eq 'PARTIAL') {
            $limitNotes.Add('capture_status=PARTIAL')
            $limitNotes.Add('incomplete visual coverage: some screenshot captures failed validation')
        }

        $reconciliationStatus = [string]$report.evidence_reconciliation.status
        switch ($reconciliationStatus) {
            'PASS' {
                $report.status = 'PASS'
                $report.execution_status = 'SUCCESS'
                $report.execution_report.final_outcome = 'PASS'
                $report.execution_report.status_detail = $passStatus
                $report.decision_allowed = $true
                $report.decision_disabled = $false
                if ($limitNotes.Count -gt 0) {
                    $report.failure_or_limit_report = [ordered]@{
                        kind = 'LIMITS'
                        failure_summary = ''
                        notes = @($limitNotes)
                    }
                }
            }
            'PARTIAL' {
                $report.status = 'PARTIAL'
                $report.execution_status = 'PARTIAL'
                $report.execution_report.final_outcome = 'PARTIAL'
                $report.execution_report.status_detail = 'PARTIAL'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'LIMITS'
                    failure_summary = ''
                    notes = @($limitNotes + @('reconciliation_status=PARTIAL', 'downstream analysis limited'))
                }
            }
            default {
                $report.status = 'FAIL'
                $report.execution_status = 'FAILED'
                $report.execution_report.final_outcome = 'FAIL'
                $report.execution_report.status_detail = 'FAIL'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'FAILURE'
                    failure_summary = 'failure_summary.json'
                    notes = @($limitNotes + @('reconciliation_status=FAIL'))
                }
            }
        }
        if ($counterMismatchDetected) {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.summary = 'Run failed: run_budget_violation'
            $report.next_step = 'run_budget_violation'
            $report.decision_allowed = $false
            $report.decision_disabled = $true
            $report.capture_report.status = 'FAIL'
            $report.capture_report.counter_mismatch = $true
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @('run_budget_violation')
                reason = 'run_budget_violation'
            }
            $report.trust_boundary.visual_evidence = 'invalid'
            $report.trust_boundary.reason = 'run_budget_violation'
            $shouldFail = $true
            $errorCode = 'RUN_BUDGET_VIOLATION'
            $errorMessage = 'run_budget_violation'
        }

        $report.trust_boundary.decision_allowed = [bool]$report.decision_allowed
        $report.produced_artifacts = @($producedArtifacts)
    }
    catch {
        $shouldFail = $true
        $errorCode = 'LINK_FETCH_FAILED'
        $errorMessage = $_.Exception.Message
        $report.status = 'FAIL'
        $report.execution_status = 'FAILED'
        $report.summary = "Run failed: $errorCode"
        $report.next_step = $errorMessage
        $report.execution_report.final_outcome = 'FAIL'
        $report.execution_report.status_detail = 'FAIL'
        $report.failure_or_limit_report = [ordered]@{
            kind = 'FAILURE'
            failure_summary = 'failure_summary.json'
            notes = @($errorMessage)
        }
        $report.produced_artifacts = @($producedArtifacts)
        $report.linked_artifacts = @(
            [ordered]@{ name = 'run_report'; path = $runReportPath },
            [ordered]@{ name = 'failure_summary'; path = $failurePath }
        )
    }
}

if (-not (Test-Path -LiteralPath $actionReportPath)) {
    $fallbackActionReport = @(
        "Site: $BaseUrl",
        "Status: $($report.status)",
        "Outcome: $($report.execution_report.status_detail)",
        "Summary: $($report.summary)"
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($actionReportPath, $fallbackActionReport)
    Copy-Item -LiteralPath $actionReportPath -Destination $deterministicActionReportPath -Force
}

if ($shouldFail) {
    if (-not $report.failure_or_limit_report -or [string]$report.failure_or_limit_report.kind -ne 'FAILURE') {
        $report.failure_or_limit_report = [ordered]@{
            kind = 'FAILURE'
            failure_summary = 'failure_summary.json'
            notes = @($errorMessage)
        }
    }
    else {
        $report.failure_or_limit_report.kind = 'FAILURE'
        $report.failure_or_limit_report.failure_summary = 'failure_summary.json'
    }
    $failure = [ordered]@{
        error_code = $errorCode
        error_message = $errorMessage
        fail_class = 'FAILURE'
        notes = @($errorMessage)
        must_read_files = @('RUN_REPORT.json', 'visual_manifest.json')
        mode = $normalizedMode
        base_url = $BaseUrl
        status = 'FAIL'
        timestamp_utc = Get-IsoUtcNow
        run_report_path = $runReportPath
    }
    try {
        Write-JsonFile -Path $failurePath -Data $failure
    }
    catch {
        $lastResortFailure = [ordered]@{
            error_code = if ([string]::IsNullOrWhiteSpace($errorCode)) { 'FAILURE_SUMMARY_WRITE_FAILED' } else { $errorCode }
            error_message = if ([string]::IsNullOrWhiteSpace($errorMessage)) { 'failure_summary_write_failed' } else { $errorMessage }
            fail_class = 'FAILURE'
            notes = @('failure_summary_write_failed')
            must_read_files = @('RUN_REPORT.json', 'visual_manifest.json')
        }
        [System.IO.File]::WriteAllText($failurePath, ($lastResortFailure | ConvertTo-Json -Depth 10))
    }
    if (Test-Path -LiteralPath $failurePath) {
        Copy-Item -LiteralPath $failurePath -Destination $deterministicFailurePath -Force
    }
    $report.produced_artifacts = @($producedArtifacts + 'failure_summary.json')
    Write-JsonFile -Path $runReportPath -Data $report
    Copy-Item -LiteralPath $runReportPath -Destination $deterministicRunReportPath -Force
    exit 1
}

Write-JsonFile -Path $runReportPath -Data $report
Copy-Item -LiteralPath $runReportPath -Destination $deterministicRunReportPath -Force

exit 0
