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

    $json = $Data | ConvertTo-Json -Depth 30
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

function Test-HasMetricValue {
    param($Value)

    return ($null -ne $Value -and $Value -ne '')
}

function Test-HasContentMetrics {
    param($Item)

    if (-not $Item) { return $false }

    if ($Item.contentMetricsPresent -eq $true) {
        return $true
    }

    if ((Test-HasMetricValue -Value $Item.bodyTextLength) -and
        (Test-HasMetricValue -Value $Item.links) -and
        (Test-HasMetricValue -Value $Item.images)) {
        return $true
    }

    return $false
}

function Test-ContentMissing {
    param($Item)

    if (-not $Item) { return $false }
    if ($Item.status -ne 'ok') { return $false }
    if (-not (Test-HasContentMetrics -Item $Item)) { return $false }

    $bodyTextLength = [int]$Item.bodyTextLength
    $links = [int]$Item.links
    $images = [int]$Item.images
    $title = ""

    if ($null -ne $Item.title) {
        $title = [string]$Item.title
    }

    if ($bodyTextLength -lt 50 -and
        $links -eq 0 -and
        $images -eq 0 -and
        [string]::IsNullOrWhiteSpace($title)) {
        return $true
    }

    return $false
}

function Get-VisualHealthScore {
    param($Item)

    if (-not $Item) { return 0 }

    if ($Item.status -ne 'ok') {
        return 0
    }

    $hasMetrics = Test-HasContentMetrics -Item $Item

    if ($hasMetrics -and (Test-ContentMissing -Item $Item)) {
        return 0
    }

    $score = 100

    if ($Item.lowCoverage -eq $true) {
        $score -= 20
    }

    if ($hasMetrics) {
        if ($Item.suspectShortPage -eq $true) {
            $score -= 20
        }

        if ($Item.suspectEmptyTitle -eq $true) {
            $score -= 15
        }

        if ($Item.suspectFooterMissing -eq $true) {
            $score -= 10
        }

        $bodyTextLength = [int]$Item.bodyTextLength
        if ($bodyTextLength -lt 800) {
            $score -= 10
        }

        $links = [int]$Item.links
        if ($links -eq 0) {
            $score -= 10
        }

        $images = [int]$Item.images
        if ($images -eq 0) {
            $score -= 5
        }
    }

    if ($score -lt 0) {
        $score = 0
    }

    if ($score -gt 100) {
        $score = 100
    }

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
    $missingMetricRoutes = @()

    $routeScores = @()
    $findings = @()

    foreach ($item in $manifest) {
        $url = [string]$item.url
        $importance = Get-RouteImportance -Url $url
        $hasMetrics = Test-HasContentMetrics -Item $item
        $contentMissing = Test-ContentMissing -Item $item
        $score = Get-VisualHealthScore -Item $item
        $band = Get-ScoreBand -Score $score

        $bodyTextLength = $null
        if (Test-HasMetricValue -Value $item.bodyTextLength) {
            $bodyTextLength = [int]$item.bodyTextLength
        }

        $linksValue = $null
        if (Test-HasMetricValue -Value $item.links) {
            $linksValue = [int]$item.links
        }

        $imagesValue = $null
        if (Test-HasMetricValue -Value $item.images) {
            $imagesValue = [int]$item.images
        }

        $titleValue = $null
        if (Test-HasMetricValue -Value $item.title) {
            $titleValue = [string]$item.title
        }

        $routeScores += @{
            url = $url
            route_path = Get-RoutePathFromUrl -Url $url
            route_importance = $importance
            visual_health_score = $score
            score_band = $band
            status = [string]$item.status
            screenshot_count = [int]$item.screenshotCount
            content_metrics_present = $hasMetrics
            body_text_length = $bodyTextLength
            links = $linksValue
            images = $imagesValue
            title = $titleValue
            content_missing = $contentMissing
        }

        if ($item.status -ne 'ok') {
            $failedRoutes += $url
            $findings += New-Finding `
                -Severity "high" `
                -Kind "capture_fail" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route failed during visual capture"
            continue
        }

        if (-not $hasMetrics) {
            $missingMetricRoutes += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "content_metrics_missing" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Content verdict skipped because capture did not return DOM metrics"
        }

        if ($contentMissing -eq $true) {
            $contentEmptyRoutes += $url
            $findings += New-Finding `
                -Severity "high" `
                -Kind "content_missing" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route appears visually empty: no title, no text, no links, no images"
        }

        if ($item.lowCoverage -eq $true) {
            $lowCoverageRoutes += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "low_coverage" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route has fewer than 3 screenshots"
        }

        if ($hasMetrics -and $item.suspectShortPage -eq $true) {
            $suspectShortPages += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "short_page" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route body text appears too short"
        }

        if ($hasMetrics -and $item.suspectEmptyTitle -eq $true) {
            $suspectEmptyTitles += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "empty_title" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route title appears empty"
        }

        if ($hasMetrics -and $item.suspectFooterMissing -eq $true) {
            $suspectFooterMissing += $url
            $findings += New-Finding `
                -Severity "low" `
                -Kind "footer_missing" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Footer element was not detected"
        }

        if ($hasMetrics -and $linksValue -eq 0) {
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "no_links" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route has zero links"
        }

        if ($hasMetrics -and $imagesValue -eq 0) {
            $findings += New-Finding `
                -Severity "low" `
                -Kind "no_images" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route has zero images"
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
        content_metrics_missing_routes = $missingMetricRoutes
        capture_summary_present = [bool]$captureSummary
        findings_high = $highSeverityCount
        findings_medium = $mediumSeverityCount
        findings_low = $lowSeverityCount
        status = $status
    }

    Save-Json -Path (Join-Path $ReportsDir "route_scores.json") -Data $routeScores
    Save-Json -Path (Join-Path $ReportsDir "visual_summary.json") -Data $summary
    Save-Json -Path (Join-Path $ReportsDir "visual_findings.json") -Data $findings
    Save-Json -Path (Join-Path $ReportsDir "final-status.json") -Data @{ status = $status }

    @(
        "SITE AUDITOR VISUAL REPORT"
        "BASE URL: $BaseUrl"
        "ROUTES: $(@($routes).Count)"
        "SCREENSHOTS: $screenshotCount"
        "COVERAGE SCORE: $coverageScore"
        "SITE VISUAL HEALTH SCORE: $siteVisualHealthScore"
        "FAILED ROUTES: $($failedRoutes.Count)"
        "LOW COVERAGE ROUTES: $($lowCoverageRoutes.Count)"
        "CONTENT EMPTY ROUTES: $($contentEmptyRoutes.Count)"
        "CONTENT METRICS MISSING ROUTES: $($missingMetricRoutes.Count)"
        "HIGH FINDINGS: $highSeverityCount"
        "MEDIUM FINDINGS: $mediumSeverityCount"
        "LOW FINDINGS: $lowSeverityCount"
        "STATUS: $status"
    ) | Out-File -FilePath (Join-Path $ReportsDir "REPORT.txt") -Encoding utf8

    return $summary
}
