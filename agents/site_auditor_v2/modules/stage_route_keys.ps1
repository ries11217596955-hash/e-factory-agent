Set-StrictMode -Version Latest

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
            $candidateUrl = (Resolve-SafeUri -BaseUri ([Uri]$BaseUrl) -RelativeOrAbsolute $trimmedValue).AbsoluteUri
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

function Get-VisualTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [int]$MaxPages = 5
    )

    $selected = New-Object System.Collections.Generic.List[object]
    $seenRoutes = New-CaseInsensitiveKeyMap
    $tierOne = New-Object System.Collections.Generic.List[object]
    $tierTwo = New-Object System.Collections.Generic.List[object]
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
    $baseRootUrl = Get-NormalizedAbsoluteUriString -Uri $baseUri -Path '/'
    $baseNormalized = Get-NormalizedRouteResult -Url $baseRootUrl
    if (Add-KeyIfMissing -Map $seenRoutes -Key ([string]$baseNormalized.normalized_route)) {
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

        if (-not (Add-KeyIfMissing -Map $seenRoutes -Key ([string]$routeKey))) {
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
            url = (Resolve-SafeUri -BaseUri ([Uri]$BaseUrl) -RelativeOrAbsolute $routeKey).AbsoluteUri
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

    Write-Host 'ROUTE_SELECTION: VISUAL_TARGETS_MERGE_READY'
    $allRankedTargets = @(
        @($tierOne.ToArray()) +
        @($tierTwo.ToArray())
    )
    Write-Host 'ROUTE_SELECTION: VISUAL_TARGETS_OVERFLOW_READY'
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
