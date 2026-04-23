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

function Get-OwnershipMode {
    return 'EXTERNAL'
}

function Get-ActionTextByOwnership {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('OWNED', 'EXTERNAL')]
        [string]$OwnershipMode,
        [Parameter(Mandatory = $true)]
        [string]$OwnedAction,
        [Parameter(Mandatory = $true)]
        [string]$ExternalAction
    )

    if ($OwnershipMode -eq 'OWNED') {
        return $OwnedAction
    }

    return $ExternalAction
}

function Get-DefectPriorityByIssueType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IssueType
    )

    switch ($IssueType) {
        'PROCESS_FIRST' { return 'P1' }
        'NO_VALUE_FIRST_SCREEN' { return 'P1' }
        'NO_ACTION_PATH' { return 'P2' }
        'MICRO_CLUSTER' { return 'P1' }
        default { return 'P2' }
    }
}

function Get-PageSignalThresholds {
    return [ordered]@{
        thin_html_length = 1200
        thin_internal_links = 2
        first_screen_text_min_length = 80
        first_screen_text_max_length = 800
        first_screen_html_max_length = 18000
        shell_text_max_length = 40
        shell_content_tag_min_count = 2
    }
}

function Get-PageTypeHeuristic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteKey,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [int]$InternalLinkCount,
        [Parameter(Mandatory = $true)]
        [int]$ContentTagCount,
        [Parameter(Mandatory = $true)]
        [int]$WrapperTagCount
    )

    $routeLower = ([string]$RouteKey).ToLowerInvariant()
    $titleLower = ([string]$Title).ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($routeLower) -or $routeLower -eq '/') { return 'HOME' }
    if ($routeLower -match '/(compare|vs|pricing|plans|choose|decision|selector|quiz)(/|$)' -or $titleLower -match '\b(compare|versus|pricing|plan|choose)\b') { return 'DECISION' }
    if ($routeLower -match '/(tool|tools|calculator|generator|checker)(/|$)' -or $titleLower -match '\b(tool|calculator|generator|checker)\b') { return 'TOOL' }
    if ($routeLower -match '/(hub|hubs|category|categories|topics|solutions|services|directory)(/|$)') { return 'HUB' }
    if ($routeLower -match '/(blog|article|docs|guide|news|insights)(/|$)' -or $titleLower -match '\b(guide|article|blog|news|insight)\b') { return 'ARTICLE' }
    if ($InternalLinkCount -ge 12 -and $WrapperTagCount -ge $ContentTagCount) { return 'HUB' }
    if ($ContentTagCount -ge 6 -and $InternalLinkCount -le 8) { return 'ARTICLE' }

    return 'UNKNOWN'
}

function Test-PageTypeRequiresAnswer {
    param([Parameter(Mandatory = $true)][string]$PageType)
    return @('HOME', 'DECISION', 'TOOL') -contains [string]$PageType
}

function Get-FindingTypeSortRank {
    param([Parameter(Mandatory = $true)][string]$IssueType)
    switch ([string]$IssueType) {
        'MICRO_CLUSTER' { return 0 }
        'PROCESS_FIRST' { return 1 }
        'NO_VALUE_FIRST_SCREEN' { return 2 }
        'NO_ACTION_PATH' { return 3 }
        default { return 9 }
    }
}

function Get-EvidenceSnippet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $lines = @(
        ([string]$Text -split "(`r`n|`n|`r)") |
        ForEach-Object { [string]$_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 2
    )
    return [string]($lines -join ' ')
}

function Test-HighSignalConfidence {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$ConditionMet,
        [Parameter(Mandatory = $true)]
        [bool]$EvidencePresent
    )

    if ($ConditionMet -and $EvidencePresent) {
        return 'HIGH'
    }

    return 'LOW'
}

function Escape-HtmlText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-ClientReportHtml {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('RU', 'EN')]
        [string]$Language,
        [Parameter(Mandatory = $true)]
        [hashtable]$ReportPayload
    )

    $title = if ($Language -eq 'RU') { 'Отчёт аудита сайта' } else { 'Website Audit Report' }
    $executiveHeader = if ($Language -eq 'RU') { 'Итог' } else { 'Executive Verdict' }
    $checkedHeader = if ($Language -eq 'RU') { 'Что проверено' } else { 'What Was Checked' }
    $mainFindingHeader = if ($Language -eq 'RU') { 'Главное наблюдение' } else { 'Main Finding' }
    $nextHeader = if ($Language -eq 'RU') { 'Что делать дальше' } else { 'What To Do Next' }
    $impactHeader = if ($Language -eq 'RU') { 'Почему это важно' } else { 'Why It Matters' }
    $limitsHeader = if ($Language -eq 'RU') { 'Ограничения' } else { 'Limitations' }
    $snapshotHeader = if ($Language -eq 'RU') { 'Технический срез' } else { 'Technical Snapshot' }

    $executiveLines = @($ReportPayload.executive_lines | ForEach-Object { "<p>$(Escape-HtmlText -Text ([string]$_))</p>" }) -join ''
    $checkedLines = @($ReportPayload.checked_lines | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $impactLines = @($ReportPayload.impact_lines | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $limitationLines = @($ReportPayload.limitations_lines | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $actionLines = @($ReportPayload.actions_lines | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $snapshotRows = @($ReportPayload.snapshot_rows | ForEach-Object {
            "<tr><th>$(Escape-HtmlText -Text ([string]$_.label))</th><td>$(Escape-HtmlText -Text ([string]$_.value))</td></tr>"
        }) -join ''

    return @"
<!doctype html>
<html lang="$(if ($Language -eq 'RU') { 'ru' } else { 'en' })">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$(Escape-HtmlText -Text $title)</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 28px; color: #1f2937; line-height: 1.45; }
    h1 { font-size: 28px; margin-bottom: 12px; }
    h2 { font-size: 18px; margin: 20px 0 8px; }
    .box { border: 1px solid #d1d5db; background: #f9fafb; border-radius: 8px; padding: 12px 14px; }
    ul { margin: 0; padding-left: 20px; }
    p { margin: 6px 0; }
    table { border-collapse: collapse; width: 100%; max-width: 560px; }
    th, td { border: 1px solid #d1d5db; text-align: left; padding: 6px 8px; font-size: 14px; }
    th { width: 45%; background: #f3f4f6; }
  </style>
</head>
<body>
  <h1>$(Escape-HtmlText -Text $title)</h1>
  <section class="box">
    <h2>$(Escape-HtmlText -Text $executiveHeader)</h2>
    $executiveLines
  </section>
  <section>
    <h2>$(Escape-HtmlText -Text $checkedHeader)</h2>
    <ul>$checkedLines</ul>
  </section>
  <section>
    <h2>$(Escape-HtmlText -Text $mainFindingHeader)</h2>
    <p>$(Escape-HtmlText -Text ([string]$ReportPayload.main_finding))</p>
  </section>
  <section>
    <h2>$(Escape-HtmlText -Text $nextHeader)</h2>
    <ul>$actionLines</ul>
  </section>
  <section>
    <h2>$(Escape-HtmlText -Text $impactHeader)</h2>
    <ul>$impactLines</ul>
  </section>
  $(if ($ReportPayload.include_limitations) { "<section><h2>$(Escape-HtmlText -Text $limitsHeader)</h2><ul>$limitationLines</ul></section>" } else { '' })
  <section>
    <h2>$(Escape-HtmlText -Text $snapshotHeader)</h2>
    <table>$snapshotRows</table>
  </section>
</body>
</html>
"@
}

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

function Resolve-CanonicalBaseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $trimmedBaseUrl = [string]$BaseUrl
    if (-not [string]::IsNullOrWhiteSpace($trimmedBaseUrl)) {
        $trimmedBaseUrl = $trimmedBaseUrl.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($trimmedBaseUrl)) {
        return [ordered]@{
            status = 'failed'
            canonical_url = ''
            error = 'BaseUrl must be non-empty.'
        }
    }

    $candidateUrl = if ($trimmedBaseUrl -match '^[a-z][a-z0-9+\-.]*://') {
        $trimmedBaseUrl
    }
    else {
        "https://$trimmedBaseUrl"
    }

    $absoluteUri = $null
    $isAbsolute = [Uri]::TryCreate($candidateUrl, [UriKind]::Absolute, [ref]$absoluteUri)
    if (-not $isAbsolute -or $null -eq $absoluteUri) {
        return [ordered]@{
            status = 'failed'
            canonical_url = ''
            error = 'BaseUrl is not a valid absolute URL.'
        }
    }

    if ($absoluteUri.Scheme -notin @('http', 'https') -or [string]::IsNullOrWhiteSpace([string]$absoluteUri.Host)) {
        return [ordered]@{
            status = 'failed'
            canonical_url = ''
            error = 'BaseUrl must be an absolute http/https URL.'
        }
    }

    $builder = [UriBuilder]::new($absoluteUri)
    $normalizedPath = [string]$builder.Path
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        $normalizedPath = '/'
    }

    if (($normalizedPath.Length -gt 1) -and $normalizedPath.EndsWith('/')) {
        $normalizedPath = $normalizedPath.TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
            $normalizedPath = '/'
        }
    }

    $builder.Path = $normalizedPath
    $canonicalUrl = $builder.Uri.AbsoluteUri

    return [ordered]@{
        status = 'ok'
        canonical_url = $canonicalUrl
        error = ''
    }
}

function Get-ResponseHtml {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,
        [Parameter(Mandatory = $true)]
        [string]$FetchMethod
    )

    if ($FetchMethod -eq 'Invoke-WebRequest') {
        return [string]$Response.Content
    }
    elseif ($FetchMethod -eq 'Invoke-RestMethod') {
        return [string]$Response
    }
    elseif ($FetchMethod -eq 'HttpClient') {
        return [string]$Response.Content.ReadAsStringAsync().Result
    }

    throw "UNSUPPORTED_FETCH_METHOD:$FetchMethod"
}

function Get-LinkSignals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $response = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 5
    $statusCode = [int]$response.StatusCode
    $html = Get-ResponseHtml -Response $response -FetchMethod 'Invoke-WebRequest'

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
    $fetchDebug = [ordered]@{
        status_code = ''
        html_length = 0
        body_present = $false
        content_sample = ''
    }
    $rootHtml = ''
    $hrefMatches = @()
    try {
        $rootResponse = Invoke-WebRequest -Uri $RootUrl -Method Get -MaximumRedirection 5
        $rootHtml = Get-ResponseHtml -Response $rootResponse -FetchMethod 'Invoke-WebRequest'
        $fetchDebug.status_code = [string][int]$rootResponse.StatusCode
        $fetchDebug.html_length = [int]$rootHtml.Length
        $fetchDebug.body_present = ($rootHtml.Length -gt 0)
        $fetchDebug.content_sample = if ($rootHtml.Length -gt 200) { $rootHtml.Substring(0, 200) } else { $rootHtml }
        if (($fetchDebug.status_code -eq '200') -and ($fetchDebug.html_length -eq 0)) {
            throw 'FETCH_RETURNED_EMPTY_BODY'
        }
        if (($fetchDebug.body_present -eq $false) -or [string]::IsNullOrWhiteSpace($fetchDebug.content_sample)) {
            throw 'FETCH_BODY_VALIDATION_FAILED'
        }
        $hrefMatches = [regex]::Matches($rootHtml, '(?is)<a\b[^>]*href\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')
    }
    catch {
        return [ordered]@{
            root = $RootUrl
            routes = @()
            route_normalization = 'failed'
            route_normalization_errors = @('route_fetch_failed')
            fetch_debug = $fetchDebug
            raw_links_found = 0
            internal_links = 0
            filter_reason = @('fetch_failed', [string]$_.Exception.Message)
            html_snapshot = ''
            link_extraction_failed = $false
        }
    }

    $rawLinksFound = [int]$hrefMatches.Count
    $htmlSnapshot = if ($rootHtml.Length -gt 1000) { $rootHtml.Substring(0, 1000) } else { $rootHtml }
    $uniqueRouteKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $routeUrls = [System.Collections.Generic.List[object]]::new()
    $normalizationFailed = $false
    $normalizationErrors = [System.Collections.Generic.List[string]]::new()
    $internalLinkCount = 0
    $filterReasons = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
            $null = $filterReasons.Add('empty_href')
            continue
        }

        $trimmedHref = $rawHref.Trim()
        if ($trimmedHref.StartsWith('#')) {
            $null = $filterReasons.Add('invalid_format')
            continue
        }

        try {
            $resolvedUri = [Uri]::new($rootUri, $trimmedHref)
        }
        catch {
            $null = $filterReasons.Add('invalid_format')
            continue
        }

        if ($resolvedUri.Scheme -notin @('http', 'https')) {
            $null = $filterReasons.Add('invalid_format')
            continue
        }

        if ($resolvedUri.Host -ne $rootUri.Host) {
            $null = $filterReasons.Add('all_external')
            continue
        }
        $internalLinkCount += 1

        $normalizationResult = Get-NormalizedRouteResult -Url $resolvedUri.AbsoluteUri
        if ($normalizationResult.status -eq 'failed') {
            $normalizationFailed = $true
            $normalizationErrors.Add("route=$($resolvedUri.AbsoluteUri); reason=$($normalizationResult.error)")
        }

        if (($routeUrls.Count -lt $MaxRoutes) -and $uniqueRouteKeys.Add($normalizationResult.normalized_route)) {
            $routeUrls.Add($normalizationResult)
        }
    }

    $routes = [System.Collections.Generic.List[object]]::new()
    foreach ($routeTarget in $routeUrls) {
        try {
            $routeResponse = Invoke-WebRequest -Uri $routeTarget.url -Method Get -MaximumRedirection 5
            $routeHtml = Get-ResponseHtml -Response $routeResponse -FetchMethod 'Invoke-WebRequest'
            $routeTitleMatch = [regex]::Match($routeHtml, '(?is)<title[^>]*>(.*?)</title>')
            $routeTitle = if ($routeTitleMatch.Success) {
                [System.Net.WebUtility]::HtmlDecode($routeTitleMatch.Groups[1].Value).Trim()
            }
            else {
                ''
            }
            $routeStatusCode = [int]$routeResponse.StatusCode
            $routeHtmlLength = [int]$routeHtml.Length
            $pageThresholds = Get-PageSignalThresholds

            $internalRouteLinks = 0
            $routeHrefMatches = [regex]::Matches($routeHtml, '(?is)<a\b[^>]*href\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')
            foreach ($routeHrefMatch in $routeHrefMatches) {
                $rawRouteHref = if (-not [string]::IsNullOrWhiteSpace($routeHrefMatch.Groups[2].Value)) {
                    $routeHrefMatch.Groups[2].Value
                }
                elseif (-not [string]::IsNullOrWhiteSpace($routeHrefMatch.Groups[3].Value)) {
                    $routeHrefMatch.Groups[3].Value
                }
                else {
                    $routeHrefMatch.Groups[4].Value
                }
                if ([string]::IsNullOrWhiteSpace($rawRouteHref)) {
                    continue
                }

                try {
                    $resolvedRouteHref = [Uri]::new([Uri]$routeTarget.url, $rawRouteHref.Trim())
                    if ($resolvedRouteHref.Scheme -in @('http', 'https') -and $resolvedRouteHref.Host -eq $rootUri.Host) {
                        $internalRouteLinks += 1
                    }
                }
                catch { }
            }

            $htmlWithoutNoise = [regex]::Replace($routeHtml, '(?is)<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>|<noscript\b[^>]*>.*?</noscript>', ' ')
            $htmlWithoutTags = [regex]::Replace($htmlWithoutNoise, '(?is)<[^>]+>', ' ')
            $normalizedText = [regex]::Replace([System.Net.WebUtility]::HtmlDecode($htmlWithoutTags), '\s+', ' ').Trim()
            $firstScreenTextLength = if ($normalizedText.Length -gt [int]$pageThresholds.first_screen_text_max_length) { [int]$pageThresholds.first_screen_text_max_length } else { $normalizedText.Length }
            $firstScreenTextSample = if ($firstScreenTextLength -gt 0) { $normalizedText.Substring(0, $firstScreenTextLength) } else { '' }
            $firstScreenTextPresent = ($firstScreenTextSample.Length -ge [int]$pageThresholds.first_screen_text_min_length)
            $firstScreenHtmlLength = if ($routeHtml.Length -gt [int]$pageThresholds.first_screen_html_max_length) { [int]$pageThresholds.first_screen_html_max_length } else { $routeHtml.Length }
            $firstScreenHtmlSample = if ($firstScreenHtmlLength -gt 0) { $routeHtml.Substring(0, $firstScreenHtmlLength) } else { '' }

            $contentTagCount = [int]([regex]::Matches($routeHtml, '(?is)<(main|article|section|p|h1|h2|h3)\b').Count)
            $wrapperTagCount = [int]([regex]::Matches($routeHtml, '(?is)<(div|nav|header|footer)\b').Count)
            $titlePresent = (-not [string]::IsNullOrWhiteSpace($routeTitle))
            $pageType = Get-PageTypeHeuristic -RouteKey ([string]$routeTarget.normalized_route) -Title $routeTitle -InternalLinkCount $internalRouteLinks -ContentTagCount $contentTagCount -WrapperTagCount $wrapperTagCount

            $valuePattern = '\b(we help|help you|solution|solve|for teams|for businesses|for developers|what we offer|why choose|benefit|outcome|results?)\b'
            $actionPattern = '(?is)<(a|button)\b|<input\b[^>]*type\s*=\s*["'']?(submit|button)'
            $processPattern = '\b(step|steps|choose|select|follow|how it works|workflow|process)\b'
            $firstScreenTextLower = $firstScreenTextSample.ToLowerInvariant()
            $valueMatch = [regex]::Match($firstScreenTextLower, $valuePattern)
            $processMatch = [regex]::Match($firstScreenTextLower, $processPattern)
            $firstScreenHasValue = $valueMatch.Success
            $firstScreenIsProcessLike = $processMatch.Success
            $valueBeforeProcess = $false
            if ($valueMatch.Success -and $processMatch.Success) {
                $valueBeforeProcess = ($valueMatch.Index -lt $processMatch.Index)
            }
            elseif ($valueMatch.Success -and (-not $processMatch.Success)) {
                $valueBeforeProcess = $true
            }
            $firstScreenHasAction = [regex]::IsMatch($firstScreenHtmlSample, $actionPattern)

            $brokenCandidate = ($routeStatusCode -ne 200)
            $thinCandidate = (
                ($routeHtmlLength -lt [int]$pageThresholds.thin_html_length) -and
                ($internalRouteLinks -le [int]$pageThresholds.thin_internal_links) -and
                (-not $firstScreenTextPresent)
            )
            $shellLikeCandidate = (
                (-not $brokenCandidate) -and
                ($firstScreenTextSample.Length -le [int]$pageThresholds.shell_text_max_length) -and
                ($wrapperTagCount -gt $contentTagCount) -and
                ($contentTagCount -lt [int]$pageThresholds.shell_content_tag_min_count)
            )

            $classification = if ($brokenCandidate) {
                'broken'
            }
            elseif ($shellLikeCandidate) {
                'shell'
            }
            elseif ($thinCandidate) {
                'thin'
            }
            else {
                'ok'
            }

            $routes.Add([ordered]@{
                    url = $routeTarget.url
                    normalized_route = $routeTarget.normalized_route
                    status_code = $routeStatusCode
                    title = $routeTitle
                    html_length = $routeHtmlLength
                    title_present = [bool]$titlePresent
                    internal_link_count = [int]$internalRouteLinks
                    first_screen_text_length = [int]$firstScreenTextSample.Length
                    first_screen_text_present = [bool]$firstScreenTextPresent
                    content_tag_count = [int]$contentTagCount
                    wrapper_tag_count = [int]$wrapperTagCount
                    page_type = [string]$pageType
                    first_screen_text_sample = [string]$firstScreenTextSample
                    first_screen_has_value = [bool]$firstScreenHasValue
                    first_screen_has_action = [bool]$firstScreenHasAction
                    first_screen_is_process_like = [bool]$firstScreenIsProcessLike
                    value_before_process = [bool]$valueBeforeProcess
                    thin_candidate = [bool]$thinCandidate
                    shell_like_candidate = [bool]$shellLikeCandidate
                    broken_candidate = [bool]$brokenCandidate
                    classification = $classification
                })
        }
        catch {
            $routes.Add([ordered]@{
                    url = $routeTarget.url
                    normalized_route = $routeTarget.normalized_route
                    status_code = -1
                    title = ''
                    html_length = 0
                    title_present = $false
                    internal_link_count = 0
                    first_screen_text_length = 0
                    first_screen_text_present = $false
                    content_tag_count = 0
                    wrapper_tag_count = 0
                    page_type = 'UNKNOWN'
                    first_screen_text_sample = ''
                    first_screen_has_value = $false
                    first_screen_has_action = $false
                    first_screen_is_process_like = $false
                    value_before_process = $false
                    thin_candidate = $false
                    shell_like_candidate = $false
                    broken_candidate = $true
                    classification = 'broken'
                })
        }
    }

    return [ordered]@{
        root = $RootUrl
        routes = $routes
        route_normalization = if ($normalizationFailed) { 'failed' } else { 'ok' }
        route_normalization_errors = @($normalizationErrors)
        fetch_debug = $fetchDebug
        raw_links_found = [int]$rawLinksFound
        internal_links = [int]$internalLinkCount
        filter_reason = if ($internalLinkCount -eq 0) { @($filterReasons) } else { @() }
        html_snapshot = $htmlSnapshot
        link_extraction_failed = [bool](($fetchDebug.html_length -gt 0) -and ($rawLinksFound -eq 0))
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

        $normalizedRoute = $normalizedPath

        $builder = [UriBuilder]::new($uri)
        $builder.Path = $normalizedPath
        $builder.Query = [string]$uri.Query.TrimStart('?')
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

function Test-PrimaryRouteValue {
    param(
        [string]$Value
    )

    $routeValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($routeValue)) {
        return [ordered]@{ valid = $false; reason = 'empty' }
    }

    $trimmed = $routeValue.Trim()
    if (-not $trimmed.StartsWith('/')) {
        return [ordered]@{ valid = $false; reason = 'must_start_with_slash' }
    }
    if ($trimmed -match '^[a-z][a-z0-9+\-.]*://') {
        return [ordered]@{ valid = $false; reason = 'contains_scheme' }
    }
    if ($trimmed -match '#') {
        return [ordered]@{ valid = $false; reason = 'contains_fragment' }
    }
    if ($trimmed -match '\?') {
        return [ordered]@{ valid = $false; reason = 'contains_query' }
    }
    if ($trimmed -match '^//') {
        return [ordered]@{ valid = $false; reason = 'contains_host_like_prefix' }
    }
    if (($trimmed.Length -gt 1) -and $trimmed.EndsWith('/')) {
        return [ordered]@{ valid = $false; reason = 'trailing_slash_not_normalized' }
    }

    return [ordered]@{ valid = $true; reason = '' }
}

function Test-RouteContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunReport,
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [Parameter(Mandatory = $true)]
        [object]$VisualManifest
    )

    $violations = [System.Collections.Generic.List[object]]::new()
    function Add-RouteViolation {
        param(
            [string]$ArtifactPath,
            [string]$FieldPath,
            [string]$Value,
            [string]$Reason
        )
        $violations.Add([ordered]@{
                artifact_path = $ArtifactPath
                field_path = $FieldPath
                offending_value = $Value
                reason = $Reason
            })
    }

    $selectedRoutes = @($RunReport.selected_routes)
    for ($i = 0; $i -lt $selectedRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$selectedRoutes[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("selected_routes[{0}].route" -f $i) -Value ([string]$selectedRoutes[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $pageVerdicts = @($RunReport.page_verdicts)
    for ($i = 0; $i -lt $pageVerdicts.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$pageVerdicts[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("page_verdicts[{0}].route" -f $i) -Value ([string]$pageVerdicts[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $overflowRoutes = @($RunReport.run_budget.overflow_route_details)
    for ($i = 0; $i -lt $overflowRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$overflowRoutes[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("run_budget.overflow_route_details[{0}].route" -f $i) -Value ([string]$overflowRoutes[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $manifestPages = @($VisualManifest.pages)
    for ($i = 0; $i -lt $manifestPages.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$manifestPages[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'visual_manifest.json' -FieldPath ("pages[{0}].route" -f $i) -Value ([string]$manifestPages[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $summaryRoutes = @($RoutesSummary.routes)
    for ($i = 0; $i -lt $summaryRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$summaryRoutes[$i].normalized_route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'ROUTES_SUMMARY.json' -FieldPath ("routes[{0}].normalized_route" -f $i) -Value ([string]$summaryRoutes[$i].normalized_route) -Reason ([string]$testResult.reason)
        }
    }

    return [ordered]@{
        status = if ($violations.Count -eq 0) { 'ok' } else { 'failed' }
        primary_key_format = 'path_only'
        violations = @($violations)
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

        $routeValue = if ($route.PSObject.Properties['normalized_route']) {
            [string]$route.normalized_route
        }
        else {
            [string]$route.url
        }
        $canonicalRouteResult = Get-CanonicalRouteKeyResult -RouteValue $routeValue -BaseUrl $BaseUrl
        if ($canonicalRouteResult.status -ne 'ok') {
            continue
        }
        $routeKey = [string]$canonicalRouteResult.canonical_route

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
            url = [Uri]::new([Uri]$BaseUrl, $routeKey).AbsoluteUri
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
$originalBaseUrlInput = [string]$BaseUrl
$canonicalBaseUrlResult = Resolve-CanonicalBaseUrl -BaseUrl $originalBaseUrlInput
$canonicalBaseUrl = if ($canonicalBaseUrlResult.status -eq 'ok') { [string]$canonicalBaseUrlResult.canonical_url } else { '' }
$runKeyBaseUrl = if ($canonicalBaseUrlResult.status -eq 'ok') { $canonicalBaseUrl } else { $originalBaseUrlInput.Trim() }
$runKey = Get-DeterministicRunKey -Mode $Mode -BaseUrl $runKeyBaseUrl
$ownershipMode = Get-OwnershipMode
$outputRoot = Join-Path $PSScriptRoot (Join-Path 'output' $runKey)
$runReportPath = Join-Path $outputRoot 'RUN_REPORT.json'
$linkSummaryPath = Join-Path $outputRoot 'LINK_SUMMARY.json'
$routesSummaryPath = Join-Path $outputRoot 'ROUTES_SUMMARY.json'
$auditSummaryPath = Join-Path $outputRoot 'AUDIT_SUMMARY.json'
$actionSummaryPath = Join-Path $outputRoot 'ACTION_SUMMARY.json'
$actionReportPath = Join-Path $outputRoot 'ACTION_REPORT.txt'
$humanReportRuPath = Join-Path $outputRoot 'HUMAN_REPORT_RU.html'
$humanReportEnPath = Join-Path $outputRoot 'HUMAN_REPORT_EN.html'
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
$deterministicHumanReportRuPath = Join-Path $PSScriptRoot 'HUMAN_REPORT_RU.html'
$deterministicHumanReportEnPath = Join-Path $PSScriptRoot 'HUMAN_REPORT_EN.html'
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
    base_url = $canonicalBaseUrl
    ownership_mode = $ownershipMode
    input_canonicalization = [ordered]@{
        original = $originalBaseUrlInput
        canonical = $canonicalBaseUrl
        status = if ($canonicalBaseUrlResult.status -eq 'ok') { 'ok' } else { 'failed' }
    }
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
        [ordered]@{ name = 'human_report_ru'; path = $humanReportRuPath },
        [ordered]@{ name = 'human_report_en'; path = $humanReportEnPath },
        [ordered]@{ name = 'visual_manifest'; path = $visualManifestPath },
        [ordered]@{ name = 'screenshots'; path = $screenshotsPath }
    )
    problem_targets = @()
    fetch_debug = [ordered]@{
        status_code = ''
        html_length = 0
        body_present = $false
        content_sample = ''
    }
    raw_links_found = 0
    internal_links = 0
    filter_reason = @()
    html_snapshot = ''
    link_extraction_failed = $false
    operator_handoff = [ordered]@{
        deprecated = $true
        reader_role = 'ChatGPT decision/orchestration layer'
        mirrors_operator_memory_bridge = $true
        ownership_mode = $ownershipMode
        action_scope_explanation = if ($ownershipMode -eq 'OWNED') { 'Owned site: fix/update/optimize actions are allowed when supported by findings.' } else { 'External site: actions are limited to analyze/benchmark/replicate insights, not direct page fixes.' }
        must_do_before_next_task = @()
        what_to_inspect_next = @()
        truth_files = @()
        read_order = @()
        must_read_first = @('RUN_REPORT.json')
        first_file_to_open = ''
        exact_reason = ''
        do_not_do_yet = @()
        forbidden_moves = @(
            'do not guess parameter names',
            'do not generate task without reading truth_files',
            'do not patch unrelated files'
        )
        if_missing_artifact = 'Request exact missing file; do not proceed'
    }
    summary = 'LINK mode executes live fetch, route checks, and screenshot evidence capture.'
    next_step = 'Stabilize screenshot evidence quality in LINK mode.'
    report_mode = 'CLEAN'
    executive_answer = [ordered]@{
        overall_verdict = 'limited: findings layer not computed'
        primary_problem = 'audit answer layer unavailable'
        audit_scope = 'LINK mode / screenshot evidence baseline'
        strongest_next_move = 'derive deterministic findings from existing artifacts'
    }
    findings_count = 0
    limitation_count = 0
    audit_confidence = 'LOW'
    decision_summary = [ordered]@{
        primary_issue = 'NONE'
        primary_route = $null
        issue_type = 'CLEAN'
        priority = 'NONE'
        recommended_action = 'Expand audit coverage before making decisions.'
        reasoning = 'Initial placeholder before findings are synthesized.'
        ownership_mode = $ownershipMode
        audit_confidence = 'LOW'
    }
    next_strongest_move = 'Expand audit coverage before making decisions.'
    findings = @()
    operator_feed = [ordered]@{
        system_state = ''
        primary_constraint = ''
        truth_confidence = ''
        what_is_reliable = @()
        what_is_not_reliable = @()
        next_system_move = ''
        why_this_move = ''
        do_not_do_yet = @()
    }
    operator_memory_core = [ordered]@{
        who_am_i = 'system operator building site auditor agent'
        what_system_is_being_built = 'site audit agent → decision → action → monetization system'
        primary_asset = 'automation site as decision system'
        end_goal = 'traffic → decision → action → monetization'
        current_stage = ''
        current_focus = ''
        what_is_stable = @()
        what_is_unstable = @()
        agent_learned = @()
        agent_cannot_yet = @()
        agent_misleading_risk = @()
        next_capability_to_build = ''
    }
    operator_memory_bridge = [ordered]@{
        identity_anchor = [ordered]@{
            who_am_i = 'system operator building site auditor agent'
            what_system_is_being_built = 'site audit agent → decision → action → monetization system'
            primary_asset = 'automation site as decision system'
            end_goal = 'traffic → decision → action → monetization'
        }
        state_anchor = [ordered]@{
            current_stage = ''
            current_focus = ''
            what_is_stable = @()
            what_is_unstable = @()
        }
        learning_anchor = [ordered]@{
            agent_learned = @()
            agent_cannot_yet = @()
            agent_misleading_risk = @()
            next_capability_to_build = ''
        }
        must_read_contract = [ordered]@{
            must_read_files = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
            read_order = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
            first_file_to_open = 'RUN_REPORT.json'
            why_read = 'RUN_REPORT.json is the source of truth for current report state, sampled route evidence, and report-layer constraints.'
            minimum_context_after_read = 'visual truth is bounded to sampled LINK coverage, route selection is stable in-budget, and deeper interpretation remains limited without interaction/decision layers.'
        }
        next_operator_posture = [ordered]@{
            next_system_move = ''
            must_do_before_next_task = @()
            what_to_inspect_next = @()
            do_not_do_yet = @()
        }
    }
    priority_summary = [ordered]@{
        p0_count = 0
        p1_count = 0
        p2_count = 0
        limitation_count = 0
        top_issues = @()
    }
    page_verdicts = @()
    business_impact = [ordered]@{
        trust = 'unknown'
        navigation = 'unknown'
        coverage = 'unknown'
        monetization_readiness = 'unknown'
    }
    next_action_contract = [ordered]@{
        next_task_id = 'SITE_AUDITOR_V2_REPORT_LAYER_FOLLOWUP'
        next_task_objective = 'produce bounded findings from existing LINK-mode truth artifacts'
        why_this_first = 'operator needs deterministic answer contract before deeper interpretation'
        forbidden_before_done = @(
            'do not add interaction layer',
            'do not expand crawl depth',
            'do not add decision automation'
        )
    }
    decision_allowed = $true
    reconciliation_enforced = $false
    route_normalization = 'ok'
    route_contract = [ordered]@{
        status = 'ok'
        primary_key_format = 'path_only'
        violations = @()
    }
}

$shouldFail = $false
$errorCode = ''
$errorMessage = ''
$reconciliationCompleted = $false
$counterMismatchDetected = $false

if ($canonicalBaseUrlResult.status -ne 'ok') {
    $shouldFail = $true
    $errorCode = 'INVALID_BASE_URL'
    $errorMessage = [string]$canonicalBaseUrlResult.error
    $report.input_canonicalization.canonical = ''
    $report.input_canonicalization.status = 'failed'
}
else {
    $BaseUrl = $canonicalBaseUrl
    $report.base_url = $canonicalBaseUrl
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
        $report.fetch_debug = [ordered]@{
            status_code = [string]$routesSummary.fetch_debug.status_code
            html_length = [int]$routesSummary.fetch_debug.html_length
            body_present = [bool]$routesSummary.fetch_debug.body_present
            content_sample = [string]$routesSummary.fetch_debug.content_sample
        }
        $report.raw_links_found = [int]$routesSummary.raw_links_found
        $report.internal_links = [int]$routesSummary.internal_links
        $report.filter_reason = @($routesSummary.filter_reason)
        $report.html_snapshot = [string]$routesSummary.html_snapshot
        $report.link_extraction_failed = [bool]$routesSummary.link_extraction_failed
        foreach ($route in $routesSummary.routes) {
            if (-not $route.PSObject.Properties['classification']) {
                $route.classification = if ($route.status_code -ne 200) { 'broken' } elseif ($route.html_length -lt 1500) { 'thin' } else { 'ok' }
            }
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
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'fix or remove page' -ExternalAction 'analyze broken route pattern and benchmark alternatives'
                }
            }
        )
        $shellTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'shell' } |
            Sort-Object html_length, url |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'shell'
                    reason = 'shell_like_structure_with_weak_first_screen_text'
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'inspect page template/content loading for shell-only render' -ExternalAction 'note shell-like page behavior for benchmarking and reliability comparison'
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
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'expand content' -ExternalAction 'learn from richer competing pages and replicate content structure patterns'
                }
            }
        )
        $problemTargets = @($brokenTargets + $shellTargets + $thinTargets)
        $report.problem_targets = $problemTargets

        $actionSummary = [ordered]@{
            status = if ($problemTargets.Count -gt 0) { 'FINDINGS_PRESENT' } else { 'CLEAN' }
            finding_count = [int]$problemTargets.Count
            actions = @(
                $problemTargets |
                ForEach-Object {
                    [ordered]@{
                        route = [string]$_.url
                        finding_type = ([string]$_.classification).ToUpperInvariant() + '_ROUTE'
                        priority = if ([string]$_.classification -eq 'broken') { 'P0' } else { 'P1' }
                        action = [string]$_.action
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json')
                    }
                }
            )
            reason = if ($problemTargets.Count -gt 0) { 'deterministic_route_classifications_detected' } else { 'no_material_findings_in_sampled_scope' }
        }
        Write-JsonFile -Path $actionSummaryPath -Data $actionSummary
        Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
        $null = $producedArtifacts.Add('ACTION_SUMMARY.json')

        $okCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'ok' }).Count
        $shellCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'shell' }).Count
        $thinCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'thin' }).Count
        $brokenCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'broken' }).Count
        $passStatus = if (($thinCount -gt 0) -or ($shellCount -gt 0) -or ($brokenCount -gt 0)) { 'PASS_WITH_LIMITS' } else { 'PASS' }
        $auditSummary = [ordered]@{
            total = [int]@($routesSummary.routes).Count
            ok = [int]$okCount
            shell = [int]$shellCount
            thin = [int]$thinCount
            broken = [int]$brokenCount
        }
        Write-JsonFile -Path $auditSummaryPath -Data $auditSummary
        Copy-Item -LiteralPath $auditSummaryPath -Destination $deterministicAuditSummaryPath -Force
        $null = $producedArtifacts.Add('AUDIT_SUMMARY.json')

        $actionReportLines = [System.Collections.Generic.List[string]]::new()
        $actionReportLines.Add("Site: $BaseUrl")
        $actionReportLines.Add("Total pages checked: $($auditSummary.total)")
        $actionReportLines.Add("Shell: $($auditSummary.shell)")
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
                    source_url = [string]$_.url
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
        foreach ($manifestPage in @($visualManifest.pages)) {
            $manifestRouteInput = if ($manifestPage.PSObject.Properties['url']) {
                [string]$manifestPage.url
            }
            elseif ($manifestPage.PSObject.Properties['source_url']) {
                [string]$manifestPage.source_url
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($manifestRouteInput)) {
                continue
            }

            $manifestCanonicalResult = Get-CanonicalRouteKeyResult -RouteValue $manifestRouteInput -BaseUrl $BaseUrl
            if ($manifestCanonicalResult.status -ne 'ok') {
                continue
            }

            $manifestPage | Add-Member -NotePropertyName 'source_url' -NotePropertyValue $manifestRouteInput -Force
            $manifestPage | Add-Member -NotePropertyName 'route' -NotePropertyValue ([string]$manifestCanonicalResult.canonical_route) -Force
            $manifestPage.url = [Uri]::new([Uri]$BaseUrl, [string]$manifestCanonicalResult.canonical_route).AbsoluteUri
        }
        Write-JsonFile -Path $visualManifestPath -Data $visualManifest
        Copy-Item -LiteralPath $visualManifestPath -Destination $deterministicVisualManifestPath -Force
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
            $report.operator_memory_bridge.next_operator_posture.must_do_before_next_task = @(
                'review ROUTES_SUMMARY.json route coverage',
                'confirm AUDIT_SUMMARY.json counts',
                'verify ACTION_SUMMARY.json status and reason'
            )
            $report.operator_memory_bridge.next_operator_posture.what_to_inspect_next = @(
                'ROUTES_SUMMARY.json',
                'AUDIT_SUMMARY.json',
                'ACTION_SUMMARY.json'
            )
        }
        else {
            $report.operator_memory_bridge.next_operator_posture.must_do_before_next_task = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
            $report.operator_memory_bridge.next_operator_posture.what_to_inspect_next = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
        }

        $report.execution_report.final_outcome = 'PASS'
        $limitNotes = [System.Collections.Generic.List[string]]::new()
        if ($shellCount -gt 0) { $limitNotes.Add("shell_pages=$shellCount") }
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

        $routeIssueMap = @{}
        $routeSignalMap = @{}
        $findingsList = [System.Collections.Generic.List[object]]::new()
        $findingIndex = 1
        foreach ($route in @($routesSummary.routes)) {
            $routeValue = [string]$route.normalized_route
            if ([string]::IsNullOrWhiteSpace($routeValue)) { $routeValue = [string]$route.url }
            $canonicalRouteResult = Get-CanonicalRouteKeyResult -RouteValue $routeValue -BaseUrl $BaseUrl
            $routeKey = if ($canonicalRouteResult.status -eq 'ok') { [string]$canonicalRouteResult.canonical_route } else { $routeValue }
            if ([string]::IsNullOrWhiteSpace($routeKey)) { continue }
            $routeSignalMap[$routeKey] = [ordered]@{
                status_code = [int]$route.status_code
                html_length = [int]$route.html_length
                title_present = [bool]$route.title_present
                internal_link_count = [int]$route.internal_link_count
                screenshot_capture_ok = $false
                screenshot_count = 0
                top_screenshot_ok = $false
                top_screenshot_file = ''
                first_screen_text_present = [bool]$route.first_screen_text_present
                first_screen_text_sample = [string]$route.first_screen_text_sample
                first_screen_has_value = [bool]$route.first_screen_has_value
                first_screen_has_action = [bool]$route.first_screen_has_action
                first_screen_is_process_like = [bool]$route.first_screen_is_process_like
                value_before_process = [bool]$route.value_before_process
                page_type = if ($route.PSObject.Properties['page_type']) { [string]$route.page_type } else { 'UNKNOWN' }
                shell_like_candidate = [bool]$route.shell_like_candidate
                thin_candidate = [bool]$route.thin_candidate
                broken_candidate = [bool]$route.broken_candidate
            }
        }

        $manifestByRoute = @{}
        foreach ($manifestPage in @($manifestPages)) {
            $manifestUrl = [string]$manifestPage.url
            if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
                continue
            }

            $canonicalManifestRoute = Get-CanonicalRouteKeyResult -RouteValue $manifestUrl -BaseUrl $BaseUrl
            if ($canonicalManifestRoute.status -eq 'ok') {
                $manifestByRoute[[string]$canonicalManifestRoute.canonical_route] = $manifestPage
            }
        }

        $pageVerdicts = [System.Collections.Generic.List[object]]::new()
        foreach ($selectedRoute in @($report.selected_routes)) {
            $routeValue = [string]$selectedRoute.route
            $canonicalSelectedRoute = Get-CanonicalRouteKeyResult -RouteValue $routeValue -BaseUrl $BaseUrl
            $canonicalRoute = if ($canonicalSelectedRoute.status -eq 'ok') { [string]$canonicalSelectedRoute.canonical_route } else { $routeValue }
            $routeIssueCount = if ($routeIssueMap.ContainsKey($canonicalRoute)) { [int]$routeIssueMap[$canonicalRoute].Count } else { 0 }
            $routeSignals = if ($routeSignalMap.ContainsKey($canonicalRoute)) { $routeSignalMap[$canonicalRoute] } else {
                [ordered]@{
                    status_code = -1
                    html_length = 0
                    title_present = $false
                    internal_link_count = 0
                    screenshot_capture_ok = $false
                    screenshot_count = 0
                    top_screenshot_ok = $false
                    top_screenshot_file = ''
                    first_screen_text_present = $false
                    first_screen_text_sample = ''
                    first_screen_has_value = $false
                    first_screen_has_action = $false
                    first_screen_is_process_like = $false
                    value_before_process = $false
                    page_type = 'UNKNOWN'
                    shell_like_candidate = $false
                    thin_candidate = $false
                    broken_candidate = $true
                }
            }

            $visualStatus = 'unknown'
            $routeCaptureCount = 0
            $routeCaptureSuccess = 0
            $manifestRecord = $null
            if ($manifestByRoute.ContainsKey($canonicalRoute)) {
                $manifestRecord = $manifestByRoute[$canonicalRoute]
                $captureStates = @($manifestRecord.captures | ForEach-Object { [string]$_.status })
                $routeCaptureCount = [int]$captureStates.Count
                $routeCaptureSuccess = [int]@($captureStates | Where-Object { $_ -eq 'ok' }).Count
                if ($captureStates.Count -eq 0) {
                    $visualStatus = 'unknown'
                }
                elseif (@($captureStates | Where-Object { $_ -eq 'ok' }).Count -eq $captureStates.Count) {
                    $visualStatus = 'ok'
                }
                elseif (@($captureStates | Where-Object { $_ -eq 'ok' }).Count -gt 0) {
                    $visualStatus = 'partial'
                }
                else {
                    $visualStatus = 'failed'
                }
            }
            $routeSignals.screenshot_count = [int]$routeCaptureCount
            $routeSignals.screenshot_capture_ok = [bool]($routeCaptureCount -gt 0 -and $routeCaptureSuccess -eq $routeCaptureCount)
            $topCapture = if ($null -ne $manifestRecord) { @($manifestRecord.captures | Where-Object { [string]$_.segment -eq 'top' } | Select-Object -First 1)[0] } else { $null }
            if ($null -ne $topCapture) {
                $routeSignals.top_screenshot_ok = ([string]$topCapture.status -eq 'ok')
                $routeSignals.top_screenshot_file = [string]$topCapture.file
            }

            $pageType = [string]$routeSignals.page_type
            $evidenceText = Get-EvidenceSnippet -Text ([string]$routeSignals.first_screen_text_sample)
            $evidenceScreenshot = if ([bool]$routeSignals.top_screenshot_ok) { [string]$routeSignals.top_screenshot_file } else { '' }
            $evidencePresent = (-not [string]::IsNullOrWhiteSpace($evidenceText)) -and (-not [string]::IsNullOrWhiteSpace($evidenceScreenshot))
            $processCondition = [bool]$routeSignals.first_screen_is_process_like -and (-not [bool]$routeSignals.value_before_process) -and (-not [bool]$routeSignals.broken_candidate)
            $noValueCondition = (-not [bool]$routeSignals.first_screen_has_value) -and (-not [bool]$routeSignals.broken_candidate)
            $noActionCondition = (-not [bool]$routeSignals.first_screen_has_action) -and (-not [bool]$routeSignals.broken_candidate)

            $processConfidence = Test-HighSignalConfidence -ConditionMet $processCondition -EvidencePresent $evidencePresent
            $noValueConfidence = Test-HighSignalConfidence -ConditionMet $noValueCondition -EvidencePresent $evidencePresent
            $noActionConfidence = Test-HighSignalConfidence -ConditionMet $noActionCondition -EvidencePresent $evidencePresent

            if (-not $routeIssueMap.ContainsKey($canonicalRoute)) { $routeIssueMap[$canonicalRoute] = [System.Collections.Generic.List[string]]::new() }
            $defectCandidates = [System.Collections.Generic.List[string]]::new()

            if ($processConfidence -eq 'HIGH') {
                $issueType = 'PROCESS_FIRST'
                $priority = if (@('HOME', 'DECISION') -contains $pageType) { 'P0' } else { Get-DefectPriorityByIssueType -IssueType $issueType }
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        evidence_text = [string]$evidenceText
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'Key message starts with process/instructions before value is explained.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Rewrite first screen: show value before instructions' -ExternalAction 'Study pages that start with instructions instead of value'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            if ($noValueConfidence -eq 'HIGH') {
                $issueType = 'NO_VALUE_FIRST_SCREEN'
                $priority = Get-DefectPriorityByIssueType -IssueType $issueType
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        evidence_text = [string]$evidenceText
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'First screen does not clearly state what value the page provides.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear value statement to first screen' -ExternalAction 'Study pages missing a clear value statement on first screen'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            if ($noActionConfidence -eq 'HIGH') {
                $issueType = 'NO_ACTION_PATH'
                $priority = Get-DefectPriorityByIssueType -IssueType $issueType
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        evidence_text = [string]$evidenceText
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'First screen has no clear action element.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear action path in first screen' -ExternalAction 'Study pages with no first-screen action path'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            $classification = if ($defectCandidates.Count -gt 0) { 'high_signal_detected' } else { 'ok' }

            $pageVerdicts.Add([ordered]@{
                    route = $canonicalRoute
                    classification = $classification
                    signals = $routeSignals
                    defect_candidates = @($defectCandidates)
                    evidence_refs = @('ROUTES_SUMMARY.json', 'visual_manifest.json')
                    confidence = if ($defectCandidates.Count -gt 0) { 'HIGH' } elseif ($visualStatus -eq 'ok') { 'MEDIUM' } else { 'LOW' }
                })
        }

        $allFindings = @($findingsList)
        $microClusters = [System.Collections.Generic.List[object]]::new()
        $clusterSignals = @('PROCESS_FIRST', 'NO_VALUE_FIRST_SCREEN', 'NO_ACTION_PATH')
        foreach ($clusterSignal in $clusterSignals) {
            $clusterRoutes = @(
                $allFindings |
                Where-Object { [string]$_.signal_type -eq $clusterSignal -and [string]$_.confidence -eq 'HIGH' } |
                ForEach-Object { [string]$_.route } |
                Select-Object -Unique
            )
            if ($clusterRoutes.Count -ge 2) {
                $clusterPriority = if ($clusterSignal -eq 'PROCESS_FIRST') { 'P1' } else { 'P2' }
                $clusterFindingId = "F-{0:d3}" -f $findingIndex
                $microClusters.Add([ordered]@{
                        signal_type = [string]$clusterSignal
                        count = [int]$clusterRoutes.Count
                        routes = @($clusterRoutes | Select-Object -First 5)
                    })
                $allFindings += [ordered]@{
                    finding_id = $clusterFindingId
                    route = '_micro_cluster'
                    signal_type = 'MICRO_CLUSTER'
                    type = 'MICRO_CLUSTER'
                    issue_type = 'MICRO_CLUSTER'
                    category = 'DEFECT'
                    priority = $clusterPriority
                    severity = $clusterPriority
                    confidence = 'HIGH'
                    evidence_text = "$clusterSignal repeated on $([int]$clusterRoutes.Count) pages."
                    evidence_screenshot = ''
                    evidence_refs = @('RUN_REPORT.json')
                    cluster = [ordered]@{
                        signal_type = [string]$clusterSignal
                        count = [int]$clusterRoutes.Count
                        routes = @($clusterRoutes | Select-Object -First 5)
                    }
                    why_it_matters = 'Same strong signal appears across multiple pages and indicates a repeated pattern.'
                    recommended_action = if ($clusterSignal -eq 'PROCESS_FIRST') { Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Rewrite first screen: show value before instructions' -ExternalAction 'Study pages that start with instructions instead of value' } elseif ($clusterSignal -eq 'NO_VALUE_FIRST_SCREEN') { Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear value statement to first screen' -ExternalAction 'Study pages missing a clear value statement on first screen' } else { Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear action path in first screen' -ExternalAction 'Study pages with no first-screen action path' }
                }
                $findingIndex += 1
            }
        }
        $report.micro_clusters = @($microClusters)
        $defectFindings = @($allFindings | Where-Object { [string]$_.category -eq 'DEFECT' })
        $limitationFindings = [System.Collections.Generic.List[object]]::new()
        if ([int]$report.run_budget.overflow_routes -gt 0) {
            $limitationFindings.Add([ordered]@{
                    finding_id = 'limitation_route_overflow'
                    route = $null
                    signal_type = 'ROUTE_OVERFLOW_ONLY'
                    type = 'ROUTE_OVERFLOW_ONLY'
                    issue_type = 'ROUTE_OVERFLOW_ONLY'
                    category = 'LIMITATION'
                    priority = 'NONE'
                    severity = 'NONE'
                    confidence = [string]$report.audit_confidence
                    evidence_text = "Route budget excluded $([int]$report.run_budget.overflow_routes) discovered routes from this run."
                    evidence_screenshot = ''
                    evidence_refs = @('ROUTES_SUMMARY.json')
                    why_it_matters = 'Sampled coverage is bounded and can miss page-level defects outside the checked scope.'
                    recommended_action = 'Expand route sample and rerun LINK mode for broader coverage.'
                })
        }
        $limitationFindings = @($limitationFindings)
        $report.findings_count = [int]$defectFindings.Count
        $report.limitation_count = [int]$limitationFindings.Count
        $routesChecked = [int]@($report.selected_routes).Count
        $maxRoutesBudget = [int]$report.run_budget.max_routes
        $coverageRatio = if ($maxRoutesBudget -gt 0) { [double]$routesChecked / [double]$maxRoutesBudget } else { 0.0 }
        $hasLimitationFindings = ($limitationFindings.Count -gt 0)
        $isLowConfidence = ($routesChecked -lt $maxRoutesBudget) -or $hasLimitationFindings
        $isHighConfidence = (-not $isLowConfidence) -and ($defectFindings.Count -eq 0) -and ($coverageRatio -ge 0.9)
        $report.audit_confidence = if ($isLowConfidence) { 'LOW' } elseif ($isHighConfidence) { 'HIGH' } else { 'MEDIUM' }
        $p0Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P0' }).Count
        $p1Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P1' }).Count
        $p2Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P2' }).Count
        $topIssues = @(
            $defectFindings |
            Sort-Object @{ Expression = {
                    switch ([string]$_.priority) {
                        'P0' { 0 }
                        'P1' { 1 }
                        default { 2 }
                    }
                }
            }, @{ Expression = { Get-FindingTypeSortRank -IssueType ([string]$_.issue_type) } }, finding_id |
            Select-Object -First 3 |
            ForEach-Object { [string]$_.issue_type }
        )

        $report.findings = @($defectFindings + $limitationFindings)
        $operatorMemoryCore = [ordered]@{
            who_am_i = 'system operator building site auditor agent'
            what_system_is_being_built = 'site audit agent → decision → action → monetization system'
            primary_asset = 'automation site as decision system'
            end_goal = 'traffic → decision → action → monetization'
            current_stage = ''
            current_focus = ''
            what_is_stable = @()
            what_is_unstable = @()
            agent_learned = @()
            agent_cannot_yet = @()
            agent_misleading_risk = @()
            next_capability_to_build = ''
        }
        $hasOperatorFeedInputs = ($null -ne $report.capture_report -and $null -ne $report.evidence_reconciliation -and $null -ne $report.selected_routes -and $null -ne $report.run_budget -and $null -ne $report.findings)
        if ($hasOperatorFeedInputs) {
            $reconciliationStatus = [string]$report.evidence_reconciliation.status
            $captureStatus = [string]$report.capture_report.status
            $truthConfidence = if ($counterMismatchDetected -or $reconciliationStatus -eq 'FAIL' -or $captureStatus -eq 'FAIL') {
                'low'
            }
            elseif ($reconciliationStatus -eq 'PARTIAL' -or $captureStatus -eq 'PARTIAL') {
                'medium'
            }
            else {
                'high'
            }

            $stableLayer = switch ($reconciliationStatus) {
                'PASS' { 'W2 visual evidence stable' }
                'PARTIAL' { 'W2.5 visual evidence partial' }
                default { 'W2 visual evidence unstable' }
            }
            $systemChange = if (@($report.findings).Count -gt 0) { 'report layer includes deterministic findings and action mapping' } else { 'report layer is clean for sampled scope with deterministic action summary' }

            $whatIsReliable = [System.Collections.Generic.List[string]]::new()
            if ($report.capture_report.captures_success -gt 0 -and $reconciliationStatus -ne 'FAIL') {
                $null = $whatIsReliable.Add('screenshots')
            }
            if (@($report.selected_routes).Count -eq [int]$report.run_budget.selected_routes) {
                $null = $whatIsReliable.Add('route selection')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $whatIsReliable.Add('capture reconciliation')
            }
            if (@($report.findings).Count -ge 0) {
                $null = $whatIsReliable.Add('findings serialization')
            }

            $whatIsNotReliable = [System.Collections.Generic.List[string]]::new()
            if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                $null = $whatIsNotReliable.Add('complete visual evidence coverage')
            }
            if ([int]$report.run_budget.overflow_routes -gt 0) {
                $null = $whatIsNotReliable.Add('full route coverage beyond run budget')
            }
            if ($report.decision_allowed -eq $false) {
                $null = $whatIsNotReliable.Add('decision automation layer')
            }

            $primaryConstraint = if ($counterMismatchDetected) {
                'route-manifest counter mismatch blocks trustworthy downstream interpretation'
            }
            elseif ($captureStatus -eq 'FAIL') {
                'visual evidence failed and cannot support deterministic downstream interpretation'
            }
            elseif ($captureStatus -eq 'PARTIAL') {
                'visual evidence is partial and limits deterministic downstream interpretation'
            }
            elseif ([int]$report.run_budget.overflow_routes -gt 0) {
                'route budget overflow limits deterministic sampled coverage'
            }
            else {
                'sampled scope may miss issues outside current max_routes budget'
            }

            $nextSystemMove = if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                'stabilize visual evidence integrity checks in report outputs'
            }
            elseif (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                'optionally expand deterministic route sample with controlled max_routes increase'
            }
            elseif (@($report.findings).Count -eq 0) {
                'keep current CLEAN mode and rerun only when scope changes'
            }
            else {
                [string]$allFindings[0].recommended_action
            }
            $whyThisMove = if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                'stable visual truth is required before higher-level system interpretation can be trusted'
            }
            elseif (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                'clean sampled evidence is bounded; broader deterministic coverage requires a larger controlled sample'
            }
            elseif (@($report.findings).Count -eq 0) {
                'no material findings were observed in sampled routes'
            }
            else {
                'highest-severity deterministic finding should be resolved first'
            }

            $doNotDoYet = [System.Collections.Generic.List[string]]::new()
            foreach ($blockedMove in @($report.next_action_contract.forbidden_before_done)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$blockedMove)) {
                    $null = $doNotDoYet.Add([string]$blockedMove)
                }
            }
            if ($doNotDoYet.Count -eq 0) {
                $null = $doNotDoYet.Add('do not add interaction layer')
                $null = $doNotDoYet.Add('do not expand crawler depth beyond current LINK-mode budget')
            }

            $whatIsStable = [System.Collections.Generic.List[string]]::new()
            if ($report.capture_report.captures_success -gt 0) {
                $null = $whatIsStable.Add('screenshots')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $whatIsStable.Add('reconciliation')
            }
            if (@($report.selected_routes).Count -eq [int]$report.run_budget.selected_routes) {
                $null = $whatIsStable.Add('route selection')
            }

            $whatIsUnstable = [System.Collections.Generic.List[string]]::new()
            if (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                $null = $whatIsUnstable.Add('coverage beyond sampled max_routes')
            }
            if ($report.decision_allowed -eq $false) {
                $null = $whatIsUnstable.Add('decision layer')
            }
            $null = $whatIsUnstable.Add('interaction layer')

            $agentLearned = [System.Collections.Generic.List[string]]::new()
            if ($report.capture_report.captures_success -gt 0) {
                $null = $agentLearned.Add('can produce validated screenshots')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $agentLearned.Add('can reconcile evidence')
            }
            if (@($report.selected_routes).Count -gt 0) {
                $null = $agentLearned.Add('can perform deterministic route selection')
            }

            $agentCannotYet = [System.Collections.Generic.List[string]]::new()
            $null = $agentCannotYet.Add('cannot interpret UX')
            $null = $agentCannotYet.Add('cannot evaluate conversion')
            if ($report.decision_allowed -eq $false) {
                $null = $agentCannotYet.Add('cannot recommend tools')
            }

            $agentMisleadingRisk = [System.Collections.Generic.List[string]]::new()
            $null = $agentMisleadingRisk.Add('may assume page quality from visuals only')
            if ($captureStatus -eq 'PARTIAL' -or $captureStatus -eq 'FAIL') {
                $null = $agentMisleadingRisk.Add('may overstate certainty when evidence coverage is partial')
            }

            $operatorMemoryCore.current_stage = if ($reconciliationStatus -eq 'PASS' -and $captureStatus -eq 'PASS') {
                'W3 report layer'
            }
            elseif (@('PARTIAL', 'FAIL') -contains $reconciliationStatus -or @('PARTIAL', 'FAIL') -contains $captureStatus) {
                'W2/W3 report layer hardening'
            }
            else {
                ''
            }
            $operatorMemoryCore.current_focus = 'report layer'
            $operatorMemoryCore.what_is_stable = @($whatIsStable)
            $operatorMemoryCore.what_is_unstable = @($whatIsUnstable)
            $operatorMemoryCore.agent_learned = @($agentLearned)
            $operatorMemoryCore.agent_cannot_yet = @($agentCannotYet)
            $operatorMemoryCore.agent_misleading_risk = @($agentMisleadingRisk)
            $operatorMemoryCore.next_capability_to_build = if (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) { 'controlled route-sample expansion (optional)' } else { 'none required for findings-to-action layer in current scope' }

            $report.operator_feed = [ordered]@{
                system_state = "$stableLayer, $systemChange"
                primary_constraint = $primaryConstraint
                truth_confidence = $truthConfidence
                what_is_reliable = @($whatIsReliable)
                what_is_not_reliable = @($whatIsNotReliable)
                next_system_move = $nextSystemMove
                why_this_move = $whyThisMove
                do_not_do_yet = @($doNotDoYet)
            }
        }
        $report.operator_memory_core = $operatorMemoryCore
        $report.operator_memory_bridge = [ordered]@{
            identity_anchor = [ordered]@{
                who_am_i = [string]$operatorMemoryCore.who_am_i
                what_system_is_being_built = [string]$operatorMemoryCore.what_system_is_being_built
                primary_asset = [string]$operatorMemoryCore.primary_asset
                end_goal = [string]$operatorMemoryCore.end_goal
            }
            state_anchor = [ordered]@{
                current_stage = [string]$operatorMemoryCore.current_stage
                current_focus = [string]$operatorMemoryCore.current_focus
                what_is_stable = @($operatorMemoryCore.what_is_stable)
                what_is_unstable = @($operatorMemoryCore.what_is_unstable)
            }
            learning_anchor = [ordered]@{
                agent_learned = @($operatorMemoryCore.agent_learned)
                agent_cannot_yet = @($operatorMemoryCore.agent_cannot_yet)
                agent_misleading_risk = @($operatorMemoryCore.agent_misleading_risk)
                next_capability_to_build = [string]$operatorMemoryCore.next_capability_to_build
            }
            must_read_contract = [ordered]@{
                must_read_files = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
                read_order = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
                first_file_to_open = 'RUN_REPORT.json'
                why_read = if ($allFindings.Count -gt 0) { 'RUN_REPORT.json contains deterministic findings, priorities, route verdicts, and action mapping anchored to existing artifacts.' } else { 'RUN_REPORT.json confirms CLEAN sampled scope, coverage bounds, and deterministic no-finding action summary.' }
                minimum_context_after_read = if ($allFindings.Count -gt 0) { 'visual truth is trusted within sampled coverage, route selection is stable in-budget, and findings are bounded to observable LINK evidence.' } else { 'visual truth is trusted within sampled coverage, no material findings were observed, and deeper interpretation remains limited without interaction/decision layers.' }
            }
            next_operator_posture = [ordered]@{
                next_system_move = [string]$report.operator_feed.next_system_move
                must_do_before_next_task = @($report.operator_memory_bridge.next_operator_posture.must_do_before_next_task)
                what_to_inspect_next = @($report.operator_memory_bridge.next_operator_posture.what_to_inspect_next)
                do_not_do_yet = @(
                    'do not infer UX/conversion outcomes',
                    'do not grade CTA quality',
                    'do not claim monetization readiness beyond observable LINK evidence'
                )
            }
        }
        $report.page_verdicts = @($pageVerdicts)
        $report.priority_summary = [ordered]@{
            p0_count = $p0Count
            p1_count = $p1Count
            p2_count = $p2Count
            limitation_count = [int]$limitationFindings.Count
            top_issues = @($topIssues)
        }
        $report.report_mode = if ($defectFindings.Count -gt 0) { 'PROBLEM' } else { 'CLEAN' }

        $sortedFindings = @(
            $defectFindings |
            Sort-Object @{ Expression = {
                    switch ([string]$_.priority) {
                        'P0' { 0 }
                        'P1' { 1 }
                        default { 2 }
                    }
                }
            }, @{ Expression = { Get-FindingTypeSortRank -IssueType ([string]$_.issue_type) } }, finding_id
        )
        $sortedLimitationFindings = @(
            $limitationFindings |
            Sort-Object finding_id
        )

        $primaryProblem = if ($sortedFindings.Count -gt 0) { [string]$sortedFindings[0].issue_type } else { 'no_material_findings_in_sampled_scope' }
        $hasP0Defect = ($p0Count -gt 0)
        $hasP1Defect = ($p1Count -gt 0)
        $primaryDefectFinding = if ($hasP0Defect) {
            @($sortedFindings | Where-Object { [string]$_.priority -eq 'P0' } | Select-Object -First 1)[0]
        }
        elseif ($hasP1Defect) {
            @($sortedFindings | Where-Object { [string]$_.priority -eq 'P1' } | Select-Object -First 1)[0]
        }
        elseif ($sortedFindings.Count -gt 0) {
            $sortedFindings[0]
        }
        else {
            $null
        }
        $primaryLimitationFinding = if ($sortedLimitationFindings.Count -gt 0) { $sortedLimitationFindings[0] } else { $null }

        $decisionPriority = if ($null -ne $primaryDefectFinding) {
            [string]$primaryDefectFinding.priority
        }
        else {
            'NONE'
        }
        $decisionIssueType = if ($null -ne $primaryDefectFinding) {
            'DEFECT'
        }
        elseif ($null -ne $primaryLimitationFinding) {
            'LIMITATION'
        }
        else {
            'CLEAN'
        }
        $primaryIssueValue = if ($null -ne $primaryDefectFinding) {
            [string]$primaryDefectFinding.issue_type
        }
        elseif ($null -ne $primaryLimitationFinding) {
            [string]$primaryLimitationFinding.issue_type
        }
        else {
            'NONE'
        }
        $primaryRouteValue = if ($null -ne $primaryDefectFinding) {
            [string]$primaryDefectFinding.route
        }
        else {
            $null
        }
        $decisionRecommendedAction = if ($null -ne $primaryDefectFinding) {
            [string]$primaryDefectFinding.recommended_action
        }
        elseif ($null -ne $primaryLimitationFinding) {
            [string]$primaryLimitationFinding.recommended_action
        }
        elseif (@('LOW', 'MEDIUM') -contains [string]$report.audit_confidence) {
            'Expand route sample and rerun LINK mode for broader coverage.'
        }
        else {
            'Keep monitoring and rerun when the site scope changes.'
        }
        $decisionReasoning = if ($null -ne $primaryDefectFinding) {
            if ([string]$primaryDefectFinding.issue_type -eq 'MICRO_CLUSTER') {
                $clusterSignal = [string]$primaryDefectFinding.cluster.signal_type
                if ($clusterSignal -eq 'PROCESS_FIRST') { 'Key pages start with process instead of explaining value.' } elseif ($clusterSignal -eq 'NO_VALUE_FIRST_SCREEN') { 'Multiple key pages miss a clear first-screen value statement.' } else { 'Multiple key pages miss a clear first-screen action path.' }
            }
            elseif ([string]$primaryDefectFinding.issue_type -eq 'PROCESS_FIRST') {
                'Key pages start with process instead of explaining value.'
            }
            elseif ([string]$primaryDefectFinding.issue_type -eq 'NO_VALUE_FIRST_SCREEN') {
                'Key pages do not clearly explain first-screen value.'
            }
            else {
                'Key pages do not provide a clear first-screen action path.'
            }
        }
        elseif ($null -ne $primaryLimitationFinding) {
            'No page-level defect was detected, but sampled coverage limits confidence.'
        }
        else {
            if ([string]$report.audit_confidence -eq 'HIGH') { 'No page-level defects were confirmed in the checked scope.' } else { 'No page-level defects were confirmed in the checked scope.' }
        }
        $report.decision_summary = [ordered]@{
            issue_type = [string]$decisionIssueType
            primary_issue = [string]$primaryIssueValue
            primary_route = $primaryRouteValue
            priority = [string]$decisionPriority
            recommended_action = [string]$decisionRecommendedAction
            reasoning = [string]$decisionReasoning
            ownership_mode = [string]$ownershipMode
            audit_confidence = [string]$report.audit_confidence
        }
        $nextStrongestMove = [string]$report.decision_summary.recommended_action
        $overallVerdict = if ($decisionIssueType -eq 'DEFECT' -and ($report.status -eq 'PARTIAL' -or $report.status -eq 'FAIL')) {
            'DEFECT: confirmed finding(s) with limited evidence confidence'
        }
        elseif ($decisionIssueType -eq 'DEFECT') {
            'DEFECT: confirmed finding(s) in sampled LINK evidence'
        }
        elseif ($decisionIssueType -eq 'LIMITATION') {
            'LIMITATION: audit scope constraints limit coverage certainty'
        }
        elseif ([string]$report.audit_confidence -eq 'HIGH') {
            'CLEAN: No page-level defects were confirmed in the checked scope'
        }
        else {
            'CLEAN: No page-level defects were confirmed in the checked scope (coverage confidence limited)'
        }
        $report.executive_answer = [ordered]@{
            overall_verdict = $overallVerdict
            primary_problem = [string]$report.decision_summary.primary_issue
            audit_scope = 'LINK mode / screenshot evidence baseline'
            strongest_next_move = [string]$nextStrongestMove
        }
        $report.next_strongest_move = [string]$nextStrongestMove

        $report.business_impact = [ordered]@{
            trust = if ($report.capture_report.status -eq 'PASS') { 'no integrity defect detected in sampled visual evidence' } else { 'limited trust due to incomplete visual evidence' }
            navigation = if ($brokenCount -gt 0) { 'broken internal routes detected in sampled set' } else { 'no broken internal routes detected in sampled set' }
            coverage = if ($report.run_budget.overflow_routes -gt 0 -or $report.capture_report.status -ne 'PASS') { 'partial coverage in sampled LINK run' } else { 'sampled coverage complete within current run budget' }
            monetization_readiness = 'unknown (no interaction or conversion evidence in LINK mode)'
        }

        $report.next_action_contract = [ordered]@{
            next_task_id = 'SITE_AUDITOR_V2_FINDINGS_REPAIR_001'
            next_task_objective = [string]$report.decision_summary.recommended_action
            why_this_first = if ($defectFindings.Count -eq 0 -and $limitationFindings.Count -gt 0) { 'no page-level defects were detected in sampled routes, but sampling limits constrain coverage confidence' } elseif ($allFindings.Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) { 'current sampled evidence is clean; next value is controlled scope expansion only if requested' } elseif ($allFindings.Count -eq 0) { 'sampled evidence is clean and in-budget with no material finding to remediate' } elseif ($ownershipMode -eq 'EXTERNAL') { 'site is external, so findings must be converted into learnings and replication opportunities instead of direct remediation tasks' } else { 'highest-severity findings are directly evidenced and block confident downstream interpretation' }
            forbidden_before_done = @(
                'do not add interaction layer',
                'do not add decision automation',
                'do not expand crawler depth beyond current LINK-mode budget'
            )
        }
        $actionSummaryActions = [System.Collections.Generic.List[object]]::new()
        $actionSummaryActions.Add([ordered]@{
                action = [string]$report.decision_summary.recommended_action
                why = [string]$report.decision_summary.reasoning
                priority = [string]$report.decision_summary.priority
            })
        if ($actionSummaryActions.Count -lt 3 -and $decisionIssueType -eq 'DEFECT' -and $sortedFindings.Count -gt 1) {
            foreach ($finding in @($sortedFindings | Select-Object -Skip 1)) {
                if ($actionSummaryActions.Count -ge 3) { break }
                $actionSummaryActions.Add([ordered]@{
                        action = [string]$finding.recommended_action
                        why = [string]$finding.why_it_matters
                        priority = [string]$finding.priority
                    })
            }
        }
        elseif ($actionSummaryActions.Count -lt 3 -and $decisionIssueType -eq 'LIMITATION' -and $sortedLimitationFindings.Count -gt 1) {
            foreach ($limitation in @($sortedLimitationFindings | Select-Object -Skip 1)) {
                if ($actionSummaryActions.Count -ge 3) { break }
                $actionSummaryActions.Add([ordered]@{
                        action = [string]$limitation.recommended_action
                        why = [string]$limitation.why_it_matters
                        priority = [string]$limitation.priority
                    })
            }
        }
        elseif ($actionSummaryActions.Count -lt 3 -and $decisionIssueType -eq 'CLEAN' -and [string]$report.audit_confidence -ne 'HIGH') {
            $actionSummaryActions.Add([ordered]@{
                    action = 'Expand route sample and rerun LINK mode for broader coverage.'
                    why = 'Current checked scope may not represent full site behavior.'
                    priority = 'P2'
                })
        }
        $finalActionSummary = [ordered]@{
            status = if ($defectFindings.Count -gt 0) { 'FINDINGS_PRESENT' } elseif ($limitationFindings.Count -gt 0) { 'LIMITATION_ONLY' } else { 'CLEAN' }
            finding_count = [int]$defectFindings.Count
            limitation_count = [int]$limitationFindings.Count
            actions = @($actionSummaryActions)
            reason = if ($defectFindings.Count -gt 0) { 'deterministic_findings_generated_from_link_truth_artifacts' } elseif ($limitationFindings.Count -gt 0) { 'audit_limited_by_route_sampling_budget' } else { 'no_material_findings_in_sampled_scope' }
        }
        Write-JsonFile -Path $actionSummaryPath -Data $finalActionSummary
        Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
        $null = $producedArtifacts.Add('HUMAN_REPORT_RU.html')
        $null = $producedArtifacts.Add('HUMAN_REPORT_EN.html')

        $mainFindingEn = if ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'MICRO_CLUSTER') {
            [string]$report.decision_summary.reasoning
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'NO_ACTION_PATH') {
            'User has no clear next step.'
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'NO_VALUE_FIRST_SCREEN') {
            'Page does not clearly explain first-screen value.'
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'PROCESS_FIRST') {
            'Page starts with instructions instead of explanation.'
        }
        elseif ($decisionIssueType -eq 'DEFECT') {
            "Confirmed defect: $([string]$report.decision_summary.primary_issue)."
        }
        elseif ($decisionIssueType -eq 'LIMITATION') {
            "Coverage limitation: this is an audit scope constraint, not a page defect ($([string]$report.decision_summary.primary_issue))."
        }
        else {
            'No page-level defects were confirmed in the checked scope.'
        }
        $mainFindingRu = if ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'MICRO_CLUSTER') {
            [string]$report.decision_summary.reasoning
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'NO_ACTION_PATH') {
            'У пользователя нет понятного следующего шага.'
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'NO_VALUE_FIRST_SCREEN') {
            'Страница не объясняет ценность на первом экране.'
        }
        elseif ($decisionIssueType -eq 'DEFECT' -and [string]$report.decision_summary.primary_issue -eq 'PROCESS_FIRST') {
            'Страница начинается с инструкций вместо объяснения ценности.'
        }
        elseif ($decisionIssueType -eq 'DEFECT') {
            "Подтверждён дефект: $([string]$report.decision_summary.primary_issue)."
        }
        elseif ($decisionIssueType -eq 'LIMITATION') {
            "Ограничение покрытия: это ограничение аудита, а не дефект страницы ($([string]$report.decision_summary.primary_issue))."
        }
        else {
            'Дефекты уровня страницы в проверенном объёме не подтверждены.'
        }
        $limitationsCommon = [System.Collections.Generic.List[string]]::new()
        if ([string]$report.audit_confidence -ne 'HIGH' -or $limitationFindings.Count -gt 0) {
            $limitationsCommon.Add('Checked scope may be partial and may not cover all site pages.')
            if ([int]$report.run_budget.overflow_routes -gt 0) {
                $limitationsCommon.Add("Route budget excluded $([int]$report.run_budget.overflow_routes) discovered routes from this run.")
            }
        }
        $snapshotRowsEn = @(
            [ordered]@{ label = 'Pages checked'; value = [string]$routesChecked },
            [ordered]@{ label = 'Findings count'; value = [string]$allFindings.Count },
            [ordered]@{ label = 'Highest priority'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Confidence'; value = [string]$report.audit_confidence }
        )
        $snapshotRowsRu = @(
            [ordered]@{ label = 'Проверено страниц'; value = [string]$routesChecked },
            [ordered]@{ label = 'Количество находок'; value = [string]$allFindings.Count },
            [ordered]@{ label = 'Максимальный приоритет'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Уверенность'; value = [string]$report.audit_confidence }
        )
        $supportingExamples = @($sortedFindings | Where-Object { [string]$_.route -ne '_micro_cluster' } | Select-Object -First 2)
        $supportingLinesEn = if ($supportingExamples.Count -gt 0) { @($supportingExamples | ForEach-Object { "Example: $([string]$_.route) — $([string]$_.issue_type)." }) } else { @('No strong issue examples in sampled scope.') }
        $supportingLinesRu = if ($supportingExamples.Count -gt 0) { @($supportingExamples | ForEach-Object { "Пример: $([string]$_.route) — $([string]$_.issue_type)." }) } else { @('В проверенном объёме нет подтверждённых сильных дефектов.') }
        $reportPayloadEn = [ordered]@{
            executive_lines = @(
                "Current status: $overallVerdict.",
                "Confidence: $([string]$report.audit_confidence).",
                "Ownership context: $ownershipMode.",
                "Main conclusion: $([string]$report.decision_summary.recommended_action)"
            )
            checked_lines = @(
                "Checked routes/pages: $routesChecked.",
                "Screenshots captured: $([string]$report.capture_report.captures_success) successful of $([string]$report.capture_report.captures_attempted) attempted."
            )
            main_finding = $mainFindingEn
            actions_lines = @([string]$report.decision_summary.recommended_action)
            impact_lines = @($supportingLinesEn)
            limitations_lines = @($limitationsCommon)
            include_limitations = ($limitationsCommon.Count -gt 0)
            snapshot_rows = $snapshotRowsEn
        }
        $reportPayloadRu = [ordered]@{
            executive_lines = @(
                "Текущий статус: $overallVerdict.",
                "Уверенность: $([string]$report.audit_confidence).",
                "Контекст владения: $ownershipMode.",
                "Главный вывод: $([string]$report.decision_summary.recommended_action)"
            )
            checked_lines = @(
                "Проверено маршрутов/страниц: $routesChecked.",
                "Скриншоты: успешно $([string]$report.capture_report.captures_success) из $([string]$report.capture_report.captures_attempted)."
            )
            main_finding = $mainFindingRu
            actions_lines = @([string]$report.decision_summary.recommended_action)
            impact_lines = @($supportingLinesRu)
            limitations_lines = @($limitationsCommon | ForEach-Object { if ($_ -eq 'Checked scope may be partial and may not cover all site pages.') { 'Проверенный объём может быть частичным и не охватывать все страницы сайта.' } else { "Бюджет маршрутов исключил $([int]$report.run_budget.overflow_routes) найденных маршрутов из этого запуска." } })
            include_limitations = ($limitationsCommon.Count -gt 0)
            snapshot_rows = $snapshotRowsRu
        }
        $ruHtml = New-ClientReportHtml -Language 'RU' -ReportPayload $reportPayloadRu
        $enHtml = New-ClientReportHtml -Language 'EN' -ReportPayload $reportPayloadEn
        [System.IO.File]::WriteAllText($humanReportRuPath, $ruHtml, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($humanReportEnPath, $enHtml, [System.Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath $humanReportRuPath -Destination $deterministicHumanReportRuPath -Force
        Copy-Item -LiteralPath $humanReportEnPath -Destination $deterministicHumanReportEnPath -Force

        if ([string]$report.next_strongest_move -ne [string]$report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: next_strongest_move mismatch.' }
        if ($finalActionSummary.actions.Count -eq 0 -or [string]$finalActionSummary.actions[0].action -ne [string]$report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: ACTION_SUMMARY first action mismatch.' }
        if ([string]$reportPayloadRu.actions_lines[0] -ne [string]$report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: RU main action mismatch.' }
        if ([string]$reportPayloadEn.actions_lines[0] -ne [string]$report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: EN main action mismatch.' }
        if ([string]::IsNullOrWhiteSpace([string]$report.decision_summary.issue_type) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.primary_issue) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.priority) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.recommended_action) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.reasoning) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.ownership_mode) -or [string]::IsNullOrWhiteSpace([string]$report.decision_summary.audit_confidence)) { throw 'CONSISTENCY_LOCK_FAILED: decision_summary has null critical fields.' }
        if ([string]$report.decision_summary.issue_type -eq 'DEFECT' -and [string]::IsNullOrWhiteSpace([string]$report.decision_summary.primary_route)) { throw 'CONSISTENCY_LOCK_FAILED: defect decision missing primary_route.' }
        if ([string]$report.decision_summary.issue_type -ne 'DEFECT' -and $null -ne $report.decision_summary.primary_route -and -not [string]::IsNullOrWhiteSpace([string]$report.decision_summary.primary_route)) { throw 'CONSISTENCY_LOCK_FAILED: non-defect decision must not set primary_route.' }
        if ($decisionIssueType -eq 'LIMITATION' -and $defectFindings.Count -gt 0) { throw 'CONSISTENCY_LOCK_FAILED: limitation classified despite defect findings.' }
        if ($decisionIssueType -eq 'DEFECT' -and $defectFindings.Count -eq 0) { throw 'CONSISTENCY_LOCK_FAILED: defect classified without defect findings.' }
        if ($decisionIssueType -eq 'CLEAN' -and ($defectFindings.Count -gt 0 -or $limitationFindings.Count -gt 0)) { throw 'CONSISTENCY_LOCK_FAILED: clean classified despite findings.' }
        if ($decisionIssueType -eq 'LIMITATION' -and [string]$reportPayloadEn.main_finding -match 'Confirmed defect') { throw 'CONSISTENCY_LOCK_FAILED: limitation presented as defect in EN report.' }
        if ($decisionIssueType -eq 'LIMITATION' -and [string]$reportPayloadRu.main_finding -match 'Подтверждён дефект') { throw 'CONSISTENCY_LOCK_FAILED: limitation presented as defect in RU report.' }

        $report.next_step = [string]$nextStrongestMove
        $isLimitationOnly = ($defectFindings.Count -eq 0 -and $limitationFindings.Count -gt 0)
        $operatorHandoffReason = if ([string]$report.audit_confidence -eq 'LOW') {
            'Confidence is low because sampled route coverage is limited; avoid strong claims.'
        }
        elseif ([string]$report.audit_confidence -eq 'HIGH' -and $defectFindings.Count -eq 0) {
            'No defects detected.'
        }
        elseif ($isLimitationOnly) {
            'Run completed successfully: no page-level defects detected; audit limited by sampling and route budget constraints.'
        }
        elseif ($allFindings.Count -gt 0) {
            'RUN_REPORT.json contains sampled-scope findings, priority counts, and artifact-linked actions bounded to observable LINK evidence.'
        }
        else {
            'RUN_REPORT.json confirms sampled-scope cleanliness in current LINK coverage and documents route budget limits.'
        }
        $firstDefectAction = if ($actionSummaryActions.Count -gt 0) { [string]$actionSummaryActions[0].action } else { [string]$nextStrongestMove }
        $highestPriorityIssue = [string]$primaryIssueValue
        $report.operator_handoff = [ordered]@{
            deprecated = $true
            reader_role = 'ChatGPT decision/orchestration layer'
            mirrors_operator_memory_bridge = $true
            ownership_mode = $ownershipMode
            action_scope_explanation = if ($ownershipMode -eq 'OWNED') { 'Owned site: recommendations may include fix/update/optimize actions grounded in findings evidence.' } else { 'External site: recommendations are limited to analyze/learn/replicate patterns and traffic insights, not direct page changes.' }
            truth_files = @($report.operator_memory_bridge.must_read_contract.must_read_files)
            read_order = @($report.operator_memory_bridge.must_read_contract.read_order)
            must_read_first = @('RUN_REPORT.json')
            first_file_to_open = [string]$report.operator_memory_bridge.must_read_contract.first_file_to_open
            exact_reason = [string]$operatorHandoffReason
            issue_type = [string]$decisionIssueType
            audit_confidence = [string]$report.audit_confidence
            scope_limited = [bool]([string]$report.audit_confidence -eq 'LOW' -or [int]$report.run_budget.overflow_routes -gt 0)
            highest_priority_issue = $highestPriorityIssue
            what_to_do_first = $firstDefectAction
            do_not_do_yet = @($report.operator_memory_bridge.next_operator_posture.do_not_do_yet)
            must_do_before_next_task = @($report.operator_memory_bridge.next_operator_posture.must_do_before_next_task)
            what_to_inspect_next = @($report.operator_memory_bridge.next_operator_posture.what_to_inspect_next)
            forbidden_moves = @(
                'do not guess parameter names',
                'do not generate task without reading truth_files',
                'do not patch unrelated files'
            )
            if_missing_artifact = 'Request exact missing file; do not proceed'
        }
        $report.trust_boundary.decision_allowed = [bool]$report.decision_allowed
        $routeContractResult = Test-RouteContract -RunReport $report -RoutesSummary $routesSummary -VisualManifest $visualManifest
        $report.route_contract = [ordered]@{
            status = [string]$routeContractResult.status
            primary_key_format = [string]$routeContractResult.primary_key_format
            violations = @($routeContractResult.violations)
        }
        if ($routeContractResult.status -ne 'ok') {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.summary = 'Run failed: ROUTE_CONTRACT_BREACH'
            $report.next_step = 'Fix route contract violations and rerun LINK mode.'
            $report.decision_allowed = $false
            $report.decision_disabled = $true
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @('ROUTE_CONTRACT_BREACH')
            }
            if ($null -ne $report.trust_boundary) {
                $report.trust_boundary.visual_evidence = 'invalid'
                $report.trust_boundary.reason = 'ROUTE_CONTRACT_BREACH'
                $report.trust_boundary.decision_allowed = $false
            }
            $shouldFail = $true
            $errorCode = 'ROUTE_CONTRACT_BREACH'
            $errorMessage = 'Primary route fields must use canonical path-only route identities.'
        }
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

$actionSummaryMissingOrEmpty = (-not (Test-Path -LiteralPath $actionSummaryPath)) -or ((Get-Item -LiteralPath $actionSummaryPath).Length -le 2)
if ($actionSummaryMissingOrEmpty) {
    $fallbackActionSummary = [ordered]@{
        status = if ($shouldFail) { 'FAILED' } else { 'CLEAN' }
        finding_count = 0
        limitation_count = 0
        actions = @(
            [ordered]@{
                action = [string]$report.decision_summary.recommended_action
                why = 'Fallback action generated to keep decision chain non-empty.'
                priority = [string]$report.decision_summary.priority
            }
        )
        reason = if ($shouldFail) { 'action_summary_not_generated_before_failure' } else { 'no_material_findings_in_sampled_scope' }
    }
    Write-JsonFile -Path $actionSummaryPath -Data $fallbackActionSummary
    Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
}

if ((-not (Test-Path -LiteralPath $humanReportRuPath)) -or (-not (Test-Path -LiteralPath $humanReportEnPath))) {
    $fallbackPayloadEn = [ordered]@{
        executive_lines = @("Current status: $([string]$report.summary).", "Confidence: $([string]$report.audit_confidence).", "Ownership context: $ownershipMode.", "Main conclusion: $([string]$report.decision_summary.recommended_action)")
        checked_lines = @("Checked routes/pages: $([int]@($report.selected_routes).Count).", 'Screenshots captured: limited.', 'Coverage limited: yes.')
        main_finding = 'Report generated from fallback path after incomplete run.'
        actions_lines = @([string]$report.decision_summary.recommended_action)
        impact_lines = @('Fallback report preserves a deterministic single next action.')
        limitations_lines = @('Checked scope may be partial.')
        include_limitations = $true
        snapshot_rows = @(
            [ordered]@{ label = 'Pages checked'; value = [string][int]@($report.selected_routes).Count },
            [ordered]@{ label = 'Findings count'; value = [string]([int]$report.findings_count + [int]$report.limitation_count) },
            [ordered]@{ label = 'Highest priority'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Confidence'; value = [string]$report.audit_confidence }
        )
    }
    $fallbackPayloadRu = [ordered]@{
        executive_lines = @("Текущий статус: $([string]$report.summary).", "Уверенность: $([string]$report.audit_confidence).", "Контекст владения: $ownershipMode.", "Главный вывод: $([string]$report.decision_summary.recommended_action)")
        checked_lines = @("Проверено маршрутов/страниц: $([int]@($report.selected_routes).Count).", 'Скриншоты: ограниченно.', 'Покрытие ограничено: да.')
        main_finding = 'Отчёт сформирован в резервном режиме после неполного запуска.'
        actions_lines = @([string]$report.decision_summary.recommended_action)
        impact_lines = @('Резервный отчёт сохраняет единое приоритетное действие.')
        limitations_lines = @('Проверенный объём может быть частичным.')
        include_limitations = $true
        snapshot_rows = @(
            [ordered]@{ label = 'Проверено страниц'; value = [string][int]@($report.selected_routes).Count },
            [ordered]@{ label = 'Количество находок'; value = [string]([int]$report.findings_count + [int]$report.limitation_count) },
            [ordered]@{ label = 'Максимальный приоритет'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Уверенность'; value = [string]$report.audit_confidence }
        )
    }
    [System.IO.File]::WriteAllText($humanReportRuPath, (New-ClientReportHtml -Language 'RU' -ReportPayload $fallbackPayloadRu), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($humanReportEnPath, (New-ClientReportHtml -Language 'EN' -ReportPayload $fallbackPayloadEn), [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $humanReportRuPath -Destination $deterministicHumanReportRuPath -Force
    Copy-Item -LiteralPath $humanReportEnPath -Destination $deterministicHumanReportEnPath -Force
}
if ((Test-Path -LiteralPath $humanReportRuPath) -and (-not ($producedArtifacts -contains 'HUMAN_REPORT_RU.html'))) {
    $null = $producedArtifacts.Add('HUMAN_REPORT_RU.html')
}
if ((Test-Path -LiteralPath $humanReportEnPath) -and (-not ($producedArtifacts -contains 'HUMAN_REPORT_EN.html'))) {
    $null = $producedArtifacts.Add('HUMAN_REPORT_EN.html')
}

$report.produced_artifacts = @($producedArtifacts)

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
        fail_reason = $errorCode
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
    if ($errorCode -eq 'ROUTE_CONTRACT_BREACH' -and $null -ne $report.route_contract) {
        $failure.route_contract_violations = @($report.route_contract.violations)
    }
    try {
        Write-JsonFile -Path $failurePath -Data $failure
    }
    catch {
        $lastResortFailure = [ordered]@{
            error_code = if ([string]::IsNullOrWhiteSpace($errorCode)) { 'FAILURE_SUMMARY_WRITE_FAILED' } else { $errorCode }
            fail_reason = if ([string]::IsNullOrWhiteSpace($errorCode)) { 'FAILURE_SUMMARY_WRITE_FAILED' } else { $errorCode }
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
