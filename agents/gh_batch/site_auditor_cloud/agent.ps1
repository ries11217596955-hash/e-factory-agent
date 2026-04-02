function Build-RouteInventory {
    param($BaseUrl)

    if (-not $BaseUrl) {
        throw "BaseUrl required"
    }

    $base = $BaseUrl.TrimEnd('/')

    $routes = @(
        '/',
        '/hubs/',
        '/tools/',
        '/start-here/',
        '/search/'
    ) | Select-Object -Unique

    $full = @()
    foreach ($r in $routes) {
        $full += ($base + $r)
    }

    return $full
}

function Save-Json {
    param($Path, $Data)

    $json = $Data | ConvertTo-Json -Depth 40
    $json | Out-File -FilePath $Path -Encoding utf8
}

function Ensure-Dir {
    param($Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonFile {
    param($Path)

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-NullSafeInt {
    param($Value, $Default = 0)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [int]$Default
    }

    try {
        return [int]$Value
    }
    catch {
        return [int]$Default
    }
}

function Get-NullSafeString {
    param($Value, $Default = "")

    if ($null -eq $Value) {
        return [string]$Default
    }

    return [string]$Value
}

function Get-RoutePathFromUrl {
    param($Url)

    try {
        $uri = [System.Uri]$Url
        $path = $uri.AbsolutePath
        if (-not $path) { return "/" }
        return $path
    }
    catch {
        return [string]$Url
    }
}

function Get-RouteImportance {
    param($Url)

    $path = Get-RoutePathFromUrl -Url $Url

    if ($path -eq "/" -or
        $path -eq "/hubs/" -or
        $path -eq "/tools/" -or
        $path -eq "/start-here/") {
        return "high"
    }

    if ($path -eq "/search/" -or
        $path -like "/hubs/*" -or
        $path -like "/category/*" -or
        $path -like "/tags/*") {
        return "medium"
    }

    return "low"
}

function Increase-Severity {
    param(
        $Severity,
        $Importance
    )

    $sev = [string]$Severity
    $imp = [string]$Importance

    if ($imp -eq "high") {
        if ($sev -eq "low") { return "medium" }
        if ($sev -eq "medium") { return "high" }
    }

    if ($imp -eq "medium") {
        if ($sev -eq "low") { return "medium" }
    }

    return $sev
}

function Test-ContentMetricsMissing {
    param($Item)

    if (-not $Item) { return $true }
    if ((Get-NullSafeString $Item.status) -ne 'ok') { return $false }

    if ($null -ne $Item.contentMetricsPresent) {
        return (-not [bool]$Item.contentMetricsPresent)
    }

    $hasTitle = -not [string]::IsNullOrWhiteSpace((Get-NullSafeString $Item.title))
    $body = Get-NullSafeInt $Item.bodyTextLength
    $links = Get-NullSafeInt $Item.links
    $images = Get-NullSafeInt $Item.images

    if ($hasTitle -or $body -gt 0 -or $links -gt 0 -or $images -gt 0) {
        return $false
    }

    return $true
}

function Test-ContentMissing {
    param($Item)

    if (-not $Item) { return $true }
    if ((Get-NullSafeString $Item.status) -ne 'ok') { return $false }
    if (Test-ContentMetricsMissing -Item $Item) { return $false }

    if ($null -ne $Item.contentLikelyMissing) {
        return [bool]$Item.contentLikelyMissing
    }

    $bodyTextLength = Get-NullSafeInt $Item.bodyTextLength
    $links = Get-NullSafeInt $Item.links
    $images = Get-NullSafeInt $Item.images
    $title = Get-NullSafeString $Item.title

    if ($bodyTextLength -lt 50 -and
        $links -eq 0 -and
        $images -eq 0 -and
        [string]::IsNullOrWhiteSpace($title)) {
        return $true
    }

    return $false
}

function Test-LowCoverage {
    param($Item)

    $explicit = $null
    if ($null -ne $Item.lowCoverage) {
        $explicit = [bool]$Item.lowCoverage
    }

    $screenshotCount = Get-NullSafeInt $Item.screenshotCount
    if ($null -ne $explicit) {
        return ($explicit -or $screenshotCount -lt 3)
    }

    return ($screenshotCount -lt 3)
}

function Get-VisualHealthScore {
    param($Item)

    if (-not $Item) { return 0 }
    if ((Get-NullSafeString $Item.status) -ne 'ok') { return 0 }
    if (Test-ContentMetricsMissing -Item $Item) { return 15 }
    if (Test-ContentMissing -Item $Item) { return 0 }

    $score = 100

    if (Test-LowCoverage -Item $Item) {
        $score -= 20
    }

    if ($Item.suspectShortPage -eq $true) {
        $score -= 15
    }

    if ($Item.suspectEmptyTitle -eq $true) {
        $score -= 15
    }

    if ($Item.suspectFooterMissing -eq $true) {
        $score -= 10
    }

    $bodyTextLength = Get-NullSafeInt $Item.bodyTextLength
    if ($bodyTextLength -lt 150) {
        $score -= 25
    }
    elseif ($bodyTextLength -lt 350) {
        $score -= 15
    }
    elseif ($bodyTextLength -lt 800) {
        $score -= 5
    }

    $links = Get-NullSafeInt $Item.links
    if ($links -eq 0) {
        $score -= 15
    }
    elseif ($links -lt 5) {
        $score -= 8
    }

    if ($null -ne $Item.images) {
        $images = Get-NullSafeInt $Item.images
        if ($images -eq 0) {
            $score -= 5
        }
    }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    return $score
}

function Get-ScoreBand {
    param($Score)

    $n = [int]$Score
    if ($n -ge 85) { return "good" }
    if ($n -ge 60) { return "watch" }
    return "poor"
}

function New-Finding {
    param(
        $Severity,
        $Kind,
        $Url,
        $RouteImportance,
        $Note
    )

    $finalSeverity = Increase-Severity -Severity $Severity -Importance $RouteImportance

    return @{
        severity = $finalSeverity
        kind = $Kind
        url = $Url
        route_importance = $RouteImportance
        note = $Note
    }
}

function Add-DecisionItem {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if ($List -contains $Text) { return }
    [void]$List.Add($Text)
}

function Limit-List {
    param(
        [array]$Items,
        [int]$Max = 3
    )

    $result = @()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($result -contains $item) { continue }
        $result += $item
        if ($result.Count -ge $Max) { break }
    }
    return $result
}

function Test-RoutePresent {
    param(
        [array]$RouteScores,
        [string]$ExactPath
    )

    foreach ($r in @($RouteScores)) {
        if ((Get-NullSafeString $r.route_path) -eq $ExactPath) {
            return $true
        }
    }

    return $false
}

function Get-RouteScoreByPath {
    param(
        [array]$RouteScores,
        [string]$ExactPath
    )

    foreach ($r in @($RouteScores)) {
        if ((Get-NullSafeString $r.route_path) -eq $ExactPath) {
            return $r
        }
    }

    return $null
}

function Get-SiteStage {
    param(
        $Summary,
        [array]$RouteScores
    )

    $failedCount = @($Summary.failed_routes).Count
    $emptyCount = @($Summary.content_empty_routes).Count
    $health = [double]$Summary.site_visual_health_score
    $coverage = [double]$Summary.coverage_score

    $hasMonetizationRoute =
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/pricing/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/offers/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/recommended-tools/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/newsletter/")

    if ($failedCount -gt 0 -or $emptyCount -gt 0 -or $coverage -lt 2) {
        return "Stage 1: Structure"
    }

    if (-not $hasMonetizationRoute) {
        return "Stage 2: Product"
    }

    if ($health -lt 85) {
        return "Stage 3: Growth"
    }

    return "Stage 4: Scale"
}

function Get-CoreProblem {
    param(
        $Summary,
        [array]$RouteScores
    )

    $failedCount = @($Summary.failed_routes).Count
    $emptyCount = @($Summary.content_empty_routes).Count
    $metricsMissing = @($Summary.content_metrics_missing_routes).Count
    $lowCoverage = @($Summary.low_coverage_routes).Count
    $search = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/search/"
    $hubs = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/hubs/"

    if ($failedCount -gt 0) {
        return "Audit coverage is still unstable because one or more key routes fail during capture."
    }

    if ($metricsMissing -gt 0) {
        return "The site is visible, but content evidence is still incomplete on key routes."
    }

    if ($emptyCount -gt 0) {
        return "The site has navigable routes, but part of the audited surface still renders as effectively empty."
    }

    if ($lowCoverage -gt 0 -and $Summary.coverage_score -lt 3) {
        return "The site has content, but visual coverage is still too shallow on important routes."
    }

    if ($null -ne $search -and [int]$search.visual_health_score -lt 60) {
        return "The site has structure and content, but discovery and user decision flow are still weak."
    }

    if ($null -ne $hubs -and [int]$hubs.visual_health_score -lt 60) {
        return "The site has a base structure, but hub pages are too thin to guide user decisions."
    }

    return "The site has content and structure, but no clear conversion or monetization path is visible in the audited route set."
}

function Get-MissingList {
    param(
        $Summary,
        [array]$RouteScores
    )

    $items = New-Object System.Collections.ArrayList

    $hasStart = Test-RoutePresent -RouteScores $RouteScores -ExactPath "/start-here/"
    $hasPricing = (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/pricing/")
    $hasOffer = (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/offers/")
    $hasNewsletter = (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/newsletter/")
    $hasSearch = Test-RoutePresent -RouteScores $RouteScores -ExactPath "/search/"
    $search = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/search/"
    $tools = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/tools/"

    if (-not ($hasPricing -or $hasOffer -or $hasNewsletter)) {
        Add-DecisionItem -List $items -Text "No dedicated monetization route detected in the audited route set."
    }

    if (-not $hasStart) {
        Add-DecisionItem -List $items -Text "No dedicated entry route detected for new users."
    }

    if ($hasSearch -and $null -ne $search -and [int]$search.visual_health_score -lt 60) {
        Add-DecisionItem -List $items -Text "No strong discovery experience is visible on the search route."
    }

    if ($null -ne $tools -and [int]$tools.links -lt 5) {
        Add-DecisionItem -List $items -Text "No strong decision layer is visible on the tools route."
    }

    if ($items.Count -eq 0) {
        Add-DecisionItem -List $items -Text "No explicit conversion layer is visible in the audited route set."
    }

    return (Limit-List -Items $items -Max 3)
}

function Get-PriorityBuckets {
    param(
        $Summary,
        [array]$RouteScores
    )

    $p0 = New-Object System.Collections.ArrayList
    $p1 = New-Object System.Collections.ArrayList
    $p2 = New-Object System.Collections.ArrayList

    foreach ($url in @($Summary.failed_routes)) {
        Add-DecisionItem -List $p0 -Text ("Restore stable visual capture for " + (Get-RoutePathFromUrl -Url $url) + ".")
    }

    foreach ($url in @($Summary.content_empty_routes)) {
        Add-DecisionItem -List $p0 -Text ("Fix empty or near-empty content on " + (Get-RoutePathFromUrl -Url $url) + ".")
    }

    foreach ($url in @($Summary.content_metrics_missing_routes)) {
        Add-DecisionItem -List $p0 -Text ("Complete content evidence for " + (Get-RoutePathFromUrl -Url $url) + " before product decisions.")
    }

    foreach ($r in @($RouteScores | Where-Object { $_.route_importance -eq 'high' -and [int]$_.visual_health_score -lt 60 })) {
        Add-DecisionItem -List $p1 -Text ("Strengthen high-value route " + $r.route_path + " because it is too thin for user decisions.")
    }

    foreach ($url in @($Summary.low_coverage_routes)) {
        $path = Get-RoutePathFromUrl -Url $url
        Add-DecisionItem -List $p1 -Text ("Increase visual depth on " + $path + " to improve audit confidence.")
    }

    if (-not (
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/pricing/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/offers/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/newsletter/")
    )) {
        Add-DecisionItem -List $p1 -Text "Add a dedicated monetization route so the site can convert traffic."
    }

    $search = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/search/"
    if ($null -ne $search -and [int]$search.visual_health_score -lt 60) {
        Add-DecisionItem -List $p2 -Text "Improve the search experience or remove it from the primary path until it is useful."
    }

    $startHere = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/start-here/"
    if ($null -ne $startHere -and [int]$startHere.links -lt 5) {
        Add-DecisionItem -List $p2 -Text "Give /start-here/ a stronger next-step path for first-time visitors."
    }

    return @{
        P0 = (Limit-List -Items $p0 -Max 5)
        P1 = (Limit-List -Items $p1 -Max 5)
        P2 = (Limit-List -Items $p2 -Max 5)
    }
}

function Get-DoNext {
    param(
        $Stage,
        $Summary,
        [array]$RouteScores
    )

    $steps = New-Object System.Collections.ArrayList

    foreach ($url in @($Summary.failed_routes)) {
        Add-DecisionItem -List $steps -Text ("Fix capture/render failure on " + (Get-RoutePathFromUrl -Url $url) + ".")
    }

    foreach ($url in @($Summary.content_empty_routes)) {
        Add-DecisionItem -List $steps -Text ("Fill " + (Get-RoutePathFromUrl -Url $url) + " with real content blocks and visible navigation.")
    }

    if (-not (
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/pricing/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/offers/") -or
        (Test-RoutePresent -RouteScores $RouteScores -ExactPath "/newsletter/")
    )) {
        Add-DecisionItem -List $steps -Text "Add one monetization route with a clear offer, affiliate block, or signup intent."
    }

    $hubs = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/hubs/"
    if ($null -ne $hubs -and [int]$hubs.visual_health_score -lt 60) {
        Add-DecisionItem -List $steps -Text "Deepen /hubs/ so it routes users into clearer topic decisions."
    }

    $search = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/search/"
    if ($null -ne $search -and [int]$search.visual_health_score -lt 60) {
        Add-DecisionItem -List $steps -Text "Either strengthen /search/ for discovery or remove it from the main user path."
    }

    $startHere = Get-RouteScoreByPath -RouteScores $RouteScores -ExactPath "/start-here/"
    if ($null -ne $startHere -and [int]$startHere.visual_health_score -lt 70) {
        Add-DecisionItem -List $steps -Text "Turn /start-here/ into a stronger entry funnel with obvious next clicks."
    }

    if ($steps.Count -eq 0) {
        Add-DecisionItem -List $steps -Text "Add one explicit conversion step to the current highest-traffic entry page."
        Add-DecisionItem -List $steps -Text "Strengthen the weakest high-value route with clearer navigation and decisions."
        Add-DecisionItem -List $steps -Text "Re-run the auditor after the route update and compare stage movement."
    }

    return (Limit-List -Items $steps -Max 3)
}

function Get-TargetState {
    param($Stage)

    switch ([string]$Stage) {
        "Stage 1: Structure" { return "The site reaches stable rendering and readable core routes with trustworthy visual coverage." }
        "Stage 2: Product" { return "The site becomes decision-ready with a clear entry path, stronger hubs/tools, and one visible conversion route." }
        "Stage 3: Growth" { return "The site becomes growth-ready with repeatable discovery, stronger user routing, and visible monetization paths." }
        default { return "The site operates as a scalable decision system with strong routing, conversion, and repeatable audit signals." }
    }
}

function Invoke-SiteAuditor {
    param($BaseUrl)

    if (-not $BaseUrl) {
        throw "BaseUrl required"
    }

    $ReportsDir = Join-Path (Get-Location) "reports"
    $ScreensDir = Join-Path $ReportsDir "screenshots"

    Ensure-Dir $ReportsDir
    Ensure-Dir $ScreensDir

    Write-Host "BASE URL: $BaseUrl"

    $routes = Build-RouteInventory -BaseUrl $BaseUrl
    $routesPath = Join-Path $ReportsDir "route_inventory.json"
    Save-Json -Path $routesPath -Data $routes

    $nodeScript = Join-Path $PSScriptRoot "capture.mjs"
    if (-not (Test-Path $nodeScript)) {
        throw "capture.mjs not found: $nodeScript"
    }

    Write-Host "RUN NODE CAPTURE"
    & node $nodeScript $BaseUrl $routesPath $ReportsDir

    if ($LASTEXITCODE -ne 0) {
        throw "Node capture failed with exit code $LASTEXITCODE"
    }

    $manifestPath = Join-Path $ReportsDir "visual_manifest.json"
    $captureSummaryPath = Join-Path $ReportsDir "visual_capture_summary.json"

    if (-not (Test-Path $manifestPath)) {
        throw "visual_manifest.json missing"
    }

    $manifest = @(Read-JsonFile -Path $manifestPath)
    $captureSummary = $null
    if (Test-Path $captureSummaryPath) {
        $captureSummary = Read-JsonFile -Path $captureSummaryPath
    }

    $screens = @(Get-ChildItem -Path $ScreensDir -Filter *.png -File -ErrorAction SilentlyContinue)
    $screenshotCount = $screens.Count

    $failedRoutes = @()
    $lowCoverageRoutes = @()
    $suspectShortPages = @()
    $suspectEmptyTitles = @()
    $suspectFooterMissing = @()
    $contentEmptyRoutes = @()
    $contentMetricsMissingRoutes = @()

    $routeScores = @()
    $findings = @()

    foreach ($item in $manifest) {
        $url = Get-NullSafeString $item.url
        $importance = Get-RouteImportance -Url $url
        $metricsMissing = Test-ContentMetricsMissing -Item $item
        $contentMissing = Test-ContentMissing -Item $item
        $score = Get-VisualHealthScore -Item $item
        $band = Get-ScoreBand -Score $score
        $screenshotPerRoute = Get-NullSafeInt $item.screenshotCount
        $bodyLength = Get-NullSafeInt $item.bodyTextLength
        $linksValue = Get-NullSafeInt $item.links
        $imagesValue = if ($null -eq $item.images) { $null } else { Get-NullSafeInt $item.images }
        $titleValue = Get-NullSafeString $item.title

        $routeScores += @{
            url = $url
            route_path = Get-RoutePathFromUrl -Url $url
            route_importance = $importance
            visual_health_score = $score
            score_band = $band
            status = Get-NullSafeString $item.status
            screenshot_count = $screenshotPerRoute
            body_text_length = $bodyLength
            links = $linksValue
            images = $imagesValue
            title = $titleValue
            content_metrics_present = (-not $metricsMissing)
            content_missing = $contentMissing
        }

        if ((Get-NullSafeString $item.status) -ne 'ok') {
            $failedRoutes += $url
            $findings += New-Finding -Severity "high" -Kind "capture_fail" -Url $url -RouteImportance $importance -Note "Route failed during visual capture"
            continue
        }

        if ($metricsMissing) {
            $contentMetricsMissingRoutes += $url
            $findings += New-Finding -Severity "high" -Kind "metrics_missing" -Url $url -RouteImportance $importance -Note "Route has screenshots but content metrics are missing"
        }

        if ($contentMissing) {
            $contentEmptyRoutes += $url
            $findings += New-Finding -Severity "high" -Kind "content_missing" -Url $url -RouteImportance $importance -Note "Route appears visually empty: no title, no text, no links, no images"
        }

        $isLowCoverage = Test-LowCoverage -Item $item
        if ($isLowCoverage) {
            $lowCoverageRoutes += $url
            $findings += New-Finding -Severity "medium" -Kind "low_coverage" -Url $url -RouteImportance $importance -Note "Route has fewer than 3 screenshots"
        }

        if ($item.suspectShortPage -eq $true -or ($bodyLength -gt 0 -and $bodyLength -lt 300)) {
            $suspectShortPages += $url
            $findings += New-Finding -Severity "medium" -Kind "short_page" -Url $url -RouteImportance $importance -Note "Route body text appears too short"
        }

        if ($item.suspectEmptyTitle -eq $true -or [string]::IsNullOrWhiteSpace($titleValue)) {
            $suspectEmptyTitles += $url
            $findings += New-Finding -Severity "medium" -Kind "empty_title" -Url $url -RouteImportance $importance -Note "Route title appears empty"
        }

        if ($item.suspectFooterMissing -eq $true) {
            $suspectFooterMissing += $url
            $findings += New-Finding -Severity "low" -Kind "footer_missing" -Url $url -RouteImportance $importance -Note "Footer element was not detected"
        }

        if (-not $metricsMissing -and $linksValue -eq 0) {
            $findings += New-Finding -Severity "medium" -Kind "no_links" -Url $url -RouteImportance $importance -Note "Route has zero links"
        }

        if (-not $metricsMissing -and $null -ne $imagesValue -and $imagesValue -eq 0) {
            $findings += New-Finding -Severity "low" -Kind "no_images" -Url $url -RouteImportance $importance -Note "Route has zero images"
        }
    }

    $coverageScore = 0
    if (@($routes).Count -gt 0) {
        $coverageScore = [math]::Round(($screenshotCount / @($routes).Count), 2)
    }

    $siteVisualHealthScore = 0
    if (@($routeScores).Count -gt 0) {
        $sum = 0
        foreach ($r in $routeScores) {
            $sum += [int]$r.visual_health_score
        }
        $siteVisualHealthScore = [math]::Round(($sum / @($routeScores).Count), 2)
    }

    $status = "FAIL_VISUAL"
    if ($screenshotCount -gt 0) {
        $status = "PASS_V3_SCREENSHOT"
    }

    if ($contentEmptyRoutes.Count -ge [Math]::Ceiling(@($routes).Count * 0.5)) {
        $status = "FAIL_CONTENT_EMPTY"
    }
    elseif ($failedRoutes.Count -gt 0 -and $screenshotCount -eq 0) {
        $status = "FAIL_VISUAL"
    }
    elseif ($lowCoverageRoutes.Count -gt 0) {
        $status = "PASS_V3_SCREENSHOT_LOW_COVERAGE"
    }

    $highSeverityCount = @($findings | Where-Object { $_.severity -eq 'high' }).Count
    $mediumSeverityCount = @($findings | Where-Object { $_.severity -eq 'medium' }).Count
    $lowSeverityCount = @($findings | Where-Object { $_.severity -eq 'low' }).Count

    $summary = @{
        base_url = $BaseUrl
        route_count = @($routes).Count
        screenshots_count = $screenshotCount
        coverage_score = $coverageScore
        site_visual_health_score = $siteVisualHealthScore
        failed_routes = $failedRoutes
        low_coverage_routes = $lowCoverageRoutes
        suspect_short_pages = $suspectShortPages
        suspect_empty_titles = $suspectEmptyTitles
        suspect_footer_missing = $suspectFooterMissing
        content_empty_routes = $contentEmptyRoutes
        content_metrics_missing_routes = $contentMetricsMissingRoutes
        capture_summary_present = [bool]$captureSummary
        findings_high = $highSeverityCount
        findings_medium = $mediumSeverityCount
        findings_low = $lowSeverityCount
        status = $status
    }

    $siteStage = Get-SiteStage -Summary $summary -RouteScores $routeScores
    $coreProblem = Get-CoreProblem -Summary $summary -RouteScores $routeScores
    $priority = Get-PriorityBuckets -Summary $summary -RouteScores $routeScores
    $missing = Get-MissingList -Summary $summary -RouteScores $routeScores
    $doNext = Get-DoNext -Stage $siteStage -Summary $summary -RouteScores $routeScores
    $targetState = Get-TargetState -Stage $siteStage

    $decision = @{
        site_stage = $siteStage
        core_problem = $coreProblem
        p0 = $priority.P0
        p1 = $priority.P1
        p2 = $priority.P2
        missing = $missing
        do_next = $doNext
        target_state_30_days = $targetState
    }

    Save-Json -Path (Join-Path $ReportsDir "route_scores.json") -Data $routeScores
    Save-Json -Path (Join-Path $ReportsDir "visual_summary.json") -Data $summary
    Save-Json -Path (Join-Path $ReportsDir "visual_findings.json") -Data $findings
    Save-Json -Path (Join-Path $ReportsDir "decision_summary.json") -Data $decision
    Save-Json -Path (Join-Path $ReportsDir "final-status.json") -Data @{ status = $status }

    $reportLines = @()
    $reportLines += "SITE AUDITOR V4 REPORT"
    $reportLines += "BASE URL: $BaseUrl"
    $reportLines += "STATUS: $status"
    $reportLines += "ROUTES: $(@($routes).Count)"
    $reportLines += "SCREENSHOTS: $screenshotCount"
    $reportLines += "COVERAGE SCORE: $coverageScore"
    $reportLines += "SITE VISUAL HEALTH SCORE: $siteVisualHealthScore"
    $reportLines += ""
    $reportLines += "SITE STAGE"
    $reportLines += $siteStage
    $reportLines += ""
    $reportLines += "CORE PROBLEM"
    $reportLines += $coreProblem
    $reportLines += ""
    $reportLines += "P0 (BLOCKERS)"
    foreach ($x in @($priority.P0)) { $reportLines += ("- " + $x) }
    if (@($priority.P0).Count -eq 0) { $reportLines += "- none" }
    $reportLines += ""
    $reportLines += "P1 (HIGH IMPACT)"
    foreach ($x in @($priority.P1)) { $reportLines += ("- " + $x) }
    if (@($priority.P1).Count -eq 0) { $reportLines += "- none" }
    $reportLines += ""
    $reportLines += "P2 (LOW)"
    foreach ($x in @($priority.P2)) { $reportLines += ("- " + $x) }
    if (@($priority.P2).Count -eq 0) { $reportLines += "- none" }
    $reportLines += ""
    $reportLines += "MISSING"
    foreach ($x in @($missing)) { $reportLines += ("- " + $x) }
    if (@($missing).Count -eq 0) { $reportLines += "- none" }
    $reportLines += ""
    $reportLines += "DO NEXT (MAX 3 STEPS)"
    $stepIndex = 1
    foreach ($x in @($doNext)) {
        $reportLines += ($stepIndex.ToString() + ". " + $x)
        $stepIndex++
    }
    if (@($doNext).Count -eq 0) { $reportLines += "1. none" }
    $reportLines += ""
    $reportLines += "TARGET STATE (NEXT 30 DAYS)"
    $reportLines += $targetState
    $reportLines += ""
    $reportLines += "RAW COUNTS"
    $reportLines += ("FAILED ROUTES: " + $failedRoutes.Count)
    $reportLines += ("LOW COVERAGE ROUTES: " + $lowCoverageRoutes.Count)
    $reportLines += ("CONTENT EMPTY ROUTES: " + $contentEmptyRoutes.Count)
    $reportLines += ("CONTENT METRICS MISSING ROUTES: " + $contentMetricsMissingRoutes.Count)
    $reportLines += ("HIGH FINDINGS: " + $highSeverityCount)
    $reportLines += ("MEDIUM FINDINGS: " + $mediumSeverityCount)
    $reportLines += ("LOW FINDINGS: " + $lowSeverityCount)

    $reportLines | Out-File -FilePath (Join-Path $ReportsDir "REPORT.txt") -Encoding utf8

    return @{
        summary = $summary
        decision = $decision
    }
}
