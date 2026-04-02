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

function Get-VisualHealthScore {
    param($Item)

    if (-not $Item) { return 0 }

    if ($Item.status -ne 'ok') {
        return 0
    }

    $score = 100

    if ($Item.lowCoverage -eq $true) {
        $score -= 20
    }

    if ($Item.suspectShortPage -eq $true) {
        $score -= 20
    }

    if ($Item.suspectEmptyTitle -eq $true) {
        $score -= 15
    }

    if ($Item.suspectFooterMissing -eq $true) {
        $score -= 10
    }

    $bodyTextLength = 0
    if ($null -ne $Item.bodyTextLength) {
        $bodyTextLength = [int]$Item.bodyTextLength
    }

    if ($bodyTextLength -lt 800) {
        $score -= 10
    }

    $links = 0
    if ($null -ne $Item.links) {
        $links = [int]$Item.links
    }

    if ($links -eq 0) {
        $score -= 10
    }

    $images = 0
    if ($null -ne $Item.images) {
        $images = [int]$Item.images
    }

    if ($images -eq 0) {
        $score -= 5
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

    $routeScores = @()
    $findings = @()

    foreach ($item in $manifest) {
        $url = [string]$item.url
        $importance = Get-RouteImportance -Url $url
        $score = Get-VisualHealthScore -Item $item
        $band = Get-ScoreBand -Score $score

        $routeScores += @{
            url = $url
            route_path = Get-RoutePathFromUrl -Url $url
            route_importance = $importance
            visual_health_score = $score
            score_band = $band
            status = [string]$item.status
            screenshot_count = [int]$item.screenshotCount
            body_text_length = [int]$item.bodyTextLength
            links = [int]$item.links
            images = [int]$item.images
            title = [string]$item.title
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

        if ($item.lowCoverage -eq $true) {
            $lowCoverageRoutes += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "low_coverage" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route has fewer than 3 screenshots"
        }

        if ($item.suspectShortPage -eq $true) {
            $suspectShortPages += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "short_page" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route body text appears too short"
        }

        if ($item.suspectEmptyTitle -eq $true) {
            $suspectEmptyTitles += $url
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "empty_title" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route title appears empty"
        }

        if ($item.suspectFooterMissing -eq $true) {
            $suspectFooterMissing += $url
            $findings += New-Finding `
                -Severity "low" `
                -Kind "footer_missing" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Footer element was not detected"
        }

        $linksValue = 0
        if ($null -ne $item.links) {
            $linksValue = [int]$item.links
        }

        if ($linksValue -eq 0) {
            $findings += New-Finding `
                -Severity "medium" `
                -Kind "no_links" `
                -Url $url `
                -RouteImportance $importance `
                -Note "Route has zero links"
        }

        $imagesValue = 0
        if ($null -ne $item.images) {
            $imagesValue = [int]$item.images
        }

        if ($imagesValue -eq 0) {
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

    if ($failedRoutes.Count -gt 0 -and $screenshotCount -eq 0) {
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
        "HIGH FINDINGS: $highSeverityCount"
        "MEDIUM FINDINGS: $mediumSeverityCount"
        "LOW FINDINGS: $lowSeverityCount"
        "STATUS: $status"
    ) | Out-File -FilePath (Join-Path $ReportsDir "REPORT.txt") -Encoding utf8

    return $summary
}
