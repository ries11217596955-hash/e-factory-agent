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

    $json = $Data | ConvertTo-Json -Depth 20
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

    foreach ($item in $manifest) {
        if ($item.status -ne 'ok') {
            $failedRoutes += [string]$item.url
        }
        if ($item.lowCoverage -eq $true) {
            $lowCoverageRoutes += [string]$item.url
        }
        if ($item.suspectShortPage -eq $true) {
            $suspectShortPages += [string]$item.url
        }
        if ($item.suspectEmptyTitle -eq $true) {
            $suspectEmptyTitles += [string]$item.url
        }
        if ($item.suspectFooterMissing -eq $true) {
            $suspectFooterMissing += [string]$item.url
        }
    }

    $coverageScore = 0
    if (@($routes).Count -gt 0) {
        $coverageScore = [math]::Round(($screenshotCount / @($routes).Count), 2)
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

    $findings = @()

    foreach ($url in $failedRoutes) {
        $findings += @{
            severity = "high"
            kind = "capture_fail"
            url = $url
            note = "Route failed during visual capture"
        }
    }

    foreach ($url in $lowCoverageRoutes) {
        $findings += @{
            severity = "medium"
            kind = "low_coverage"
            url = $url
            note = "Route has fewer than 3 screenshots"
        }
    }

    foreach ($url in $suspectShortPages) {
        $findings += @{
            severity = "medium"
            kind = "short_page"
            url = $url
            note = "Route body text appears too short"
        }
    }

    foreach ($url in $suspectEmptyTitles) {
        $findings += @{
            severity = "medium"
            kind = "empty_title"
            url = $url
            note = "Route title appears empty"
        }
    }

    foreach ($url in $suspectFooterMissing) {
        $findings += @{
            severity = "low"
            kind = "footer_missing"
            url = $url
            note = "Footer element was not detected"
        }
    }

    $summary = @{
        base_url = $BaseUrl
        route_count = @($routes).Count
        screenshots_count = $screenshotCount
        coverage_score = $coverageScore
        failed_routes = $failedRoutes
        low_coverage_routes = $lowCoverageRoutes
        suspect_short_pages = $suspectShortPages
        suspect_empty_titles = $suspectEmptyTitles
        suspect_footer_missing = $suspectFooterMissing
        capture_summary_present = [bool]$captureSummary
        status = $status
    }

    Save-Json -Path (Join-Path $ReportsDir "visual_summary.json") -Data $summary
    Save-Json -Path (Join-Path $ReportsDir "visual_findings.json") -Data $findings
    Save-Json -Path (Join-Path $ReportsDir "final-status.json") -Data @{ status = $status }

    @(
        "SITE AUDITOR VISUAL REPORT"
        "BASE URL: $BaseUrl"
        "ROUTES: $(@($routes).Count)"
        "SCREENSHOTS: $screenshotCount"
        "COVERAGE SCORE: $coverageScore"
        "FAILED ROUTES: $($failedRoutes.Count)"
        "LOW COVERAGE ROUTES: $($lowCoverageRoutes.Count)"
        "SUSPECT SHORT PAGES: $($suspectShortPages.Count)"
        "SUSPECT EMPTY TITLES: $($suspectEmptyTitles.Count)"
        "SUSPECT FOOTER MISSING: $($suspectFooterMissing.Count)"
        "STATUS: $status"
    ) | Out-File -FilePath (Join-Path $ReportsDir "REPORT.txt") -Encoding utf8

    return $summary
}
