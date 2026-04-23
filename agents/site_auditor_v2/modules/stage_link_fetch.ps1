Set-StrictMode -Version Latest

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

    $normalizedPath = [string]$absoluteUri.AbsolutePath
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        $normalizedPath = '/'
    }

    if (($normalizedPath.Length -gt 1) -and $normalizedPath.EndsWith('/')) {
        $normalizedPath = $normalizedPath.TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
            $normalizedPath = '/'
        }
    }

    $canonicalUrl = Get-NormalizedAbsoluteUriString -Uri $absoluteUri -Path $normalizedPath

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

        $normalizedUrl = Get-NormalizedAbsoluteUriString -Uri $uri -Path $normalizedPath -Query ([string]$uri.Query.TrimStart('?'))

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

function Get-HrefResolutionResult {
    param(
        [Parameter(Mandatory = $true)]
        [Uri]$RootUri,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Href
    )

    $trimmedHref = [string]$Href
    if (-not [string]::IsNullOrWhiteSpace($trimmedHref)) {
        $trimmedHref = $trimmedHref.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($trimmedHref)) {
        return [ordered]@{ status = 'rejected'; classification = 'invalid_uri'; resolved_uri = $null }
    }
    if ($trimmedHref.StartsWith('#')) {
        return [ordered]@{ status = 'rejected'; classification = 'anchor_only'; resolved_uri = $null }
    }
    if ($trimmedHref -match '^(?i)(mailto|tel|javascript):') {
        return [ordered]@{ status = 'rejected'; classification = 'unsupported_scheme'; resolved_uri = $null }
    }

    $classification = if ($trimmedHref.StartsWith('http')) { 'internal_absolute' } else { 'internal_relative' }

    if ($trimmedHref.StartsWith('/')) {
        $absolute = "$($RootUri.Scheme)://$($RootUri.Host)$trimmedHref"
    }
    elseif ($trimmedHref.StartsWith('http')) {
        $absolute = $trimmedHref
    }
    else {
        return [ordered]@{ status = 'rejected'; classification = 'invalid_uri'; resolved_uri = $null }
    }

    try {
        $resolvedUri = [uri]$absolute
    }
    catch {
        return [ordered]@{ status = 'rejected'; classification = 'invalid_uri'; resolved_uri = $null }
    }

    if ($resolvedUri.Host -ne $RootUri.Host) {
        return [ordered]@{ status = 'rejected'; classification = 'external_host'; resolved_uri = $null }
    }

    return [ordered]@{
        status = 'ok'
        classification = $classification
        resolved_uri = $resolvedUri
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
        Write-Host 'ROUTE_EXTRACTION:ROOT_FETCH_OK'
        $hrefMatches = [regex]::Matches($rootHtml, '(?is)<a\b[^>]*href\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')
        Write-Host 'ROUTE_EXTRACTION:HREF_MATCHES_READY'
    }
    catch {
        throw "ROUTE_EXTRACTION_ROOT_FETCH_EXCEPTION: $([string]$_.Exception.Message)"
    }

    $rawLinksFound = [int]$hrefMatches.Count
    $htmlSnapshot = if ($rootHtml.Length -gt 1000) { $rootHtml.Substring(0, 1000) } else { $rootHtml }
    $uniqueRouteKeys = New-CaseInsensitiveKeyMap
    $routeUrls = New-Object System.Collections.Generic.List[object]
    $normalizationFailed = $false
    $normalizationErrors = New-Object System.Collections.Generic.List[string]
    $internalLinkCount = 0
    $rejectionReasonCounts = @{}
    $sampleRejectedHrefs = New-Object System.Collections.Generic.List[object]
    $sampleInternalHrefs = New-Object System.Collections.Generic.List[object]

    try {
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

            $resolution = Get-HrefResolutionResult -RootUri $rootUri -Href ([string]$rawHref)
            if ($resolution.status -ne 'ok') {
                $reasonKey = [string]$resolution.classification
                if (-not $rejectionReasonCounts.ContainsKey($reasonKey)) {
                    $rejectionReasonCounts[$reasonKey] = 0
                }
                $rejectionReasonCounts[$reasonKey] = [int]$rejectionReasonCounts[$reasonKey] + 1
                if ($sampleRejectedHrefs.Count -lt 3) {
                    $sampleRejectedHrefs.Add([ordered]@{
                            href = [string]$rawHref
                            reason = $reasonKey
                        })
                }
                continue
            }
            $resolvedUri = [Uri]$resolution.resolved_uri

            $route = ([uri]$resolvedUri.AbsoluteUri).AbsolutePath
            if ([string]::IsNullOrWhiteSpace($route)) {
                $route = '/'
            }

            $internalLinkCount += 1
            if ($sampleInternalHrefs.Count -lt 3) {
                $sampleInternalHrefs.Add([ordered]@{
                        href = [string]$rawHref
                        classification = [string]$resolution.classification
                        resolved_url = [string]$resolvedUri.AbsoluteUri
                    })
            }

            if (($routeUrls.Count -lt $MaxRoutes) -and (Add-KeyIfMissing -Map $uniqueRouteKeys -Key ([string]$route))) {
                $routeUrls.Add([ordered]@{
                        status = 'ok'
                        url = [string]$resolvedUri.AbsoluteUri
                        normalized_route = [string]$route
                        source_url = [string]$resolvedUri.AbsoluteUri
                        error = ''
                    })
            }
        }
        Write-Host 'ROUTE_EXTRACTION:HREF_FILTER_LOOP_OK'
    }
    catch {
        throw "ROUTE_EXTRACTION_HREF_LOOP_EXCEPTION: $([string]$_.Exception.Message)"
    }

    $routes = New-Object System.Collections.Generic.List[object]
    try {
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
                    $resolvedRouteHref = Resolve-SafeUri -BaseUri ([Uri]$routeTarget.url) -RelativeOrAbsolute $rawRouteHref.Trim()
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
            $headlineCount = [int]([regex]::Matches($routeHtml, '(?is)<h[1-3]\b').Count)
            $articleListCount = [int]([regex]::Matches($routeHtml, '(?is)<(article|li)\b').Count)
            $timestampCount = [int]([regex]::Matches($routeHtml, '(?is)\b(\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)\w*\.?,?\s+\d{4}|[12]\d{3}-\d{2}-\d{2}|updated|published)\b').Count)
            $anchorTextMatches = [regex]::Matches($routeHtml, '(?is)<a\b[^>]*>(.*?)</a>')
            $anchorTextCounter = @{}
            foreach ($anchorTextMatch in $anchorTextMatches) {
                $anchorText = [regex]::Replace([System.Net.WebUtility]::HtmlDecode([string]$anchorTextMatch.Groups[1].Value), '\s+', ' ').Trim().ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($anchorText) -or $anchorText.Length -lt 5) { continue }
                if (-not $anchorTextCounter.ContainsKey($anchorText)) { $anchorTextCounter[$anchorText] = 0 }
                $anchorTextCounter[$anchorText] = [int]$anchorTextCounter[$anchorText] + 1
            }
            $repeatedAnchorCount = 0
            foreach ($entry in $anchorTextCounter.GetEnumerator()) {
                if ([int]$entry.Value -ge 2) { $repeatedAnchorCount += [int]$entry.Value }
            }
            $repeatedLinkBlockRatio = if ($anchorTextMatches.Count -gt 0) { [Math]::Round(([double]$repeatedAnchorCount / [double]$anchorTextMatches.Count), 4) } else { 0.0 }
            $titlePresent = (-not [string]::IsNullOrWhiteSpace($routeTitle))
            $pageType = Get-NormalizedSurfaceType -RouteKey ([string]$routeTarget.normalized_route) -Title $routeTitle -InternalLinkCount $internalRouteLinks -ContentTagCount $contentTagCount -WrapperTagCount $wrapperTagCount -HeadlineCount $headlineCount -ArticleListCount $articleListCount -RepeatedLinkBlockRatio $repeatedLinkBlockRatio -HasTimestampPatterns ($timestampCount -gt 0)

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
                    headline_count = [int]$headlineCount
                    article_list_count = [int]$articleListCount
                    repeated_link_block_ratio = [double]$repeatedLinkBlockRatio
                    has_timestamp_patterns = [bool]($timestampCount -gt 0)
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
        Write-Host 'ROUTE_EXTRACTION:ROUTE_DETAIL_LOOP_OK'
    }
    catch {
        throw "ROUTE_EXTRACTION_ROUTE_DETAIL_EXCEPTION: $([string]$_.Exception.Message)"
    }

    $topRejectionReasons = @(
        $rejectionReasonCounts.GetEnumerator() |
            Sort-Object -Property Value -Descending |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    reason = [string]$_.Key
                    count = [int]$_.Value
                }
            }
    )

    try {
        Write-Host 'ROUTE_EXTRACTION:RETURN_READY'
        return [ordered]@{
            root = $RootUrl
            routes = $routes
            route_normalization = if ($normalizationFailed) { 'failed' } else { 'ok' }
            route_normalization_errors = @($normalizationErrors)
            fetch_debug = $fetchDebug
            raw_links_found = [int]$rawLinksFound
            internal_links = [int]$internalLinkCount
            filter_reason = @($topRejectionReasons | ForEach-Object { [string]$_.reason })
            top_rejection_reasons = @($topRejectionReasons)
            sample_rejected_hrefs = @($sampleRejectedHrefs)
            sample_internal_hrefs = @($sampleInternalHrefs)
            html_snapshot = $htmlSnapshot
            link_extraction_failed = [bool](($fetchDebug.html_length -gt 0) -and ($rawLinksFound -eq 0))
        }
    }
    catch {
        throw "ROUTE_EXTRACTION_RETURN_ASSEMBLY_EXCEPTION: $([string]$_.Exception.Message)"
    }
}
