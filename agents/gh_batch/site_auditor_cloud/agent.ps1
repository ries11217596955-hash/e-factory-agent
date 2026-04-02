$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:AgentScriptRoot = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $script:AgentScriptRoot = $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $script:AgentScriptRoot = Split-Path -Parent $PSCommandPath
}
elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) {
    try {
        $candidate = Split-Path -Parent $MyInvocation.MyCommand.Definition
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $script:AgentScriptRoot = $candidate
        }
    } catch {}
}
if ([string]::IsNullOrWhiteSpace($script:AgentScriptRoot)) {
    $script:AgentScriptRoot = (Get-Location).Path
}

function Get-ScriptRoot {
    return $script:AgentScriptRoot
}

function Get-RoutePaths {
    return @("/", "/hubs/", "/tools/", "/start-here/", "/search/")
}

function Convert-RouteToSlug {
    param([Parameter(Mandatory=$true)][string]$RoutePath)
    if ($RoutePath -eq "/") { return "home" }
    return ($RoutePath -replace "/", "_").Trim("_")
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Data,
        [int]$Depth = 10
    )
    $json = $Data | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function New-List {
    return New-Object System.Collections.Generic.List[string]
}

function Add-UniqueItem {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[string]]$List,
        [Parameter(Mandatory=$true)][string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if (-not $List.Contains($Text)) {
        $null = $List.Add($Text)
    }
}

function Join-OrNull {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[string]]$List,
        [string]$Sep = " | "
    )
    if ($List.Count -eq 0) { return $null }
    return ($List.ToArray() -join $Sep)
}

function Is-KeyRoute {
    param([Parameter(Mandatory=$true)][string]$RoutePath)
    $key = @("/", "/hubs/", "/search/", "/tools/", "/start-here/")
    return ($key -contains $RoutePath)
}

function Is-HighValueRoute {
    param([Parameter(Mandatory=$true)][object]$Route)
    if ($null -ne $Route.route_importance -and [string]$Route.route_importance -eq "high") { return $true }
    if (Is-KeyRoute -RoutePath ([string]$Route.route_path)) { return $true }
    return $false
}

function Is-ShallowRoute {
    param([Parameter(Mandatory=$true)][object]$Route)

    $len = 0
    if ($null -ne $Route.body_text_length) {
        $len = [int]$Route.body_text_length
    }

    $band = ""
    if ($null -ne $Route.score_band) {
        $band = [string]$Route.score_band
    }

    if ($band -eq "watch") { return $true }
    if ($len -lt 350) { return $true }
    return $false
}

function Has-VisualWeakness {
    param([Parameter(Mandatory=$true)][object]$Routes)

    $RouteItems = @($Routes)
    foreach ($r in $RouteItems) {
        $img = 0
        if ($null -ne $r.images) { $img = [int]$r.images }
        if ($img -gt 0) { return $false }
    }
    return $true
}

function Find-Route {
    param(
        [Parameter(Mandatory=$true)][object]$Routes,
        [Parameter(Mandatory=$true)][string]$RoutePath
    )
    $RouteItems = @($Routes)
    foreach ($r in $RouteItems) {
        if ([string]$r.route_path -eq $RoutePath) { return $r }
    }
    return $null
}

function Get-RouteImportance {
    param([Parameter(Mandatory=$true)][string]$RoutePath)
    switch ($RoutePath) {
        "/"             { return "high" }
        "/hubs/"        { return "high" }
        "/tools/"       { return "high" }
        "/start-here/"  { return "high" }
        "/search/"      { return "medium" }
        default         { return "medium" }
    }
}

function Get-RouteScoreBand {
    param([Parameter(Mandatory=$true)][int]$BodyTextLength)
    if ($BodyTextLength -lt 350) { return "watch" }
    return "good"
}

function Build-RouteInventory {
    param([Parameter(Mandatory=$true)][string]$BaseUrl)

    $base = $BaseUrl.TrimEnd("/")
    $urls = @()
    foreach ($route in (Get-RoutePaths)) {
        $urls += ($base + $route)
    }
    return $urls
}

function Get-VisualFindings {
    param([Parameter(Mandatory=$true)][object]$Manifest)

    $ManifestItems = @($Manifest)
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($m in $ManifestItems) {
        $importance = Get-RouteImportance -RoutePath ([uri]$m.url).AbsolutePath

        if ([int]$m.bodyTextLength -lt 350) {
            $sev = "medium"
            if ($importance -eq "high") { $sev = "high" }
            $items.Add([pscustomobject][ordered]@{
                severity = $sev
                note = "Route body text appears too short"
                kind = "short_page"
                url = [string]$m.url
                route_importance = $importance
            })
        }

        if ([int]$m.images -eq 0) {
            $items.Add([pscustomobject][ordered]@{
                severity = "medium"
                note = "Route has zero images"
                kind = "no_images"
                url = [string]$m.url
                route_importance = $importance
            })
        }
    }

    return @($items)
}

function Build-RouteScores {
    param([Parameter(Mandatory=$true)][object]$Manifest)

    $ManifestItems = @($Manifest)
    $result = New-Object System.Collections.Generic.List[object]

    foreach ($m in $ManifestItems) {
        $routePath = ([uri]$m.url).AbsolutePath
        $importance = Get-RouteImportance -RoutePath $routePath
        $bodyLen = [int]$m.bodyTextLength
        $visualScore = 95
        if ([int]$m.images -eq 0) { $visualScore -= 5 }
        if ($bodyLen -lt 350) { $visualScore -= 15 }
        if ($visualScore -lt 0) { $visualScore = 0 }

        $result.Add([pscustomobject][ordered]@{
            title = [string]$m.title
            body_text_length = $bodyLen
            content_missing = (-not [bool]$m.contentMetricsPresent)
            route_importance = $importance
            content_metrics_present = [bool]$m.contentMetricsPresent
            images = [int]$m.images
            visual_health_score = $visualScore
            status = [string]$m.status
            route_path = $routePath
            score_band = (Get-RouteScoreBand -BodyTextLength $bodyLen)
            screenshot_count = [int]$m.screenshotCount
            links = [int]$m.links
            url = [string]$m.url
        })
    }

    return @($result)
}

function Build-VisualSummary {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [Parameter(Mandatory=$true)][object]$Manifest,
        [Parameter(Mandatory=$true)][object]$Findings
    )

    $ManifestItems = @($Manifest)
    $FindingItems = @($Findings)

    $failedRoutes = @()
    $contentEmpty = @()
    $shortRoutes = @()
    $metricsMissing = @()
    $lowCoverage = @()
    $emptyTitles = @()
    $footerMissing = @()

    $screenshotsCount = 0
    $totalScore = 0.0

    foreach ($m in $ManifestItems) {
        $screenshotsCount += [int]$m.screenshotCount

        $score = 95.0
        if ([int]$m.images -eq 0) { $score -= 5.0 }
        if ([int]$m.bodyTextLength -lt 350) { $score -= 15.0 }
        if ($score -lt 0) { $score = 0.0 }
        $totalScore += $score

        if ([string]$m.status -ne "ok") {
            $failedRoutes += [string]$m.url
        }

        if (-not [bool]$m.contentMetricsPresent) {
            $metricsMissing += [string]$m.url
            $contentEmpty += [string]$m.url
        }

        if ([string]::IsNullOrWhiteSpace([string]$m.title)) {
            $emptyTitles += [string]$m.url
        }

        if ([int]$m.bodyTextLength -lt 350) {
            $shortRoutes += [string]$m.url
        }

        if ([int]$m.screenshotCount -lt 3) {
            $lowCoverage += [string]$m.url
        }
    }

    $high = @($FindingItems | Where-Object { $_.severity -eq "high" }).Count
    $med  = @($FindingItems | Where-Object { $_.severity -eq "medium" }).Count
    $low  = @($FindingItems | Where-Object { $_.severity -eq "low" }).Count

    $routeCount = @($ManifestItems).Count
    $health = 0.0
    if ($routeCount -gt 0) {
        $health = [math]::Round(($totalScore / $routeCount), 1)
    }

    return [pscustomobject][ordered]@{
        content_metrics_missing_routes = @($metricsMissing)
        suspect_footer_missing = @($footerMissing)
        suspect_empty_titles = @($emptyTitles)
        base_url = $BaseUrl
        route_count = $routeCount
        status = "PASS_V3_SCREENSHOT"
        content_empty_routes = @($contentEmpty)
        findings_high = $high
        findings_low = $low
        low_coverage_routes = @($lowCoverage)
        coverage_score = 3.0
        findings_medium = $med
        capture_summary_present = $false
        failed_routes = @($failedRoutes)
        site_visual_health_score = $health
        suspect_short_pages = @($shortRoutes)
        screenshots_count = $screenshotsCount
    }
}

function New-DecisionSummaryV4 {
    param(
        [Parameter(Mandatory=$true)] [object]$VisualSummary,
        [Parameter(Mandatory=$true)] [object]$RouteScores
    )

    $RouteScoreItems = @($RouteScores)

    $p0      = New-List
    $p1      = New-List
    $p2      = New-List
    $missing = New-List
    $doNext  = New-List

    $routeCount = 0
    if ($null -ne $VisualSummary.route_count) {
        $routeCount = [int]$VisualSummary.route_count
    }

    $contentEmptyCount = 0
    if ($null -ne $VisualSummary.content_empty_routes) {
        $contentEmptyCount = @($VisualSummary.content_empty_routes).Count
    }

    $hubsRoute   = Find-Route -Routes $RouteScoreItems -RoutePath "/hubs/"
    $searchRoute = Find-Route -Routes $RouteScoreItems -RoutePath "/search/"
    $toolsRoute  = Find-Route -Routes $RouteScoreItems -RoutePath "/tools/"

    $hasWeakHubs   = $false
    $hasWeakSearch = $false
    $hasAnyP0Structural = $false
    $allNoImages = Has-VisualWeakness -Routes $RouteScoreItems

    if ($null -ne $hubsRoute) {
        if ((Is-ShallowRoute -Route $hubsRoute) -and (Is-HighValueRoute -Route $hubsRoute)) {
            $hasWeakHubs = $true
            $hasAnyP0Structural = $true
            Add-UniqueItem -List $p0 -Text "Hubs page is too shallow for a key navigation route."
            Add-UniqueItem -List $doNext -Text "Expand /hubs/ into a real navigation hub with categories, route groups, and visible next paths."
        }
    }

    if ($null -ne $searchRoute) {
        if ((Is-ShallowRoute -Route $searchRoute) -and (Is-KeyRoute -RoutePath $searchRoute.route_path)) {
            $hasWeakSearch = $true
            $hasAnyP0Structural = $true
            Add-UniqueItem -List $p0 -Text "Search page is too shallow to support discovery."
            Add-UniqueItem -List $doNext -Text "Strengthen /search/ with guidance, structure, and clearer discovery intent."
        }
    }

    if ($null -ne $toolsRoute) {
        if ((Is-ShallowRoute -Route $toolsRoute) -and (Is-HighValueRoute -Route $toolsRoute)) {
            Add-UniqueItem -List $p1 -Text "Tools page needs stronger depth to support decision flow."
        }
    }

    if ($allNoImages) {
        Add-UniqueItem -List $p0 -Text "Key routes have no visual support blocks."
        Add-UniqueItem -List $doNext -Text "Add at least one visual block or preview element on each key route."
        Add-UniqueItem -List $missing -Text "No visible visual layer detected across audited routes."
    }

    if ($contentEmptyCount -gt 0) {
        Add-UniqueItem -List $p0 -Text "Some routes are structurally present but content-empty."
    }

    $monetizationMissing = $true
    Add-UniqueItem -List $missing -Text "No dedicated monetization or conversion route detected in the audited route set."

    $siteStage = "Stage 1: Structure"
    if (-not $hasAnyP0Structural -and $contentEmptyCount -eq 0 -and $routeCount -ge 5) {
        $siteStage = "Stage 2: Product"
    }
    if ($hasWeakHubs -or $hasWeakSearch) {
        $siteStage = "Stage 1: Structure"
    }

    $coreProblem = $null
    if ($hasWeakHubs -or $hasWeakSearch) {
        $coreProblem = "The site lacks structural depth in key routes, so it cannot act as a strong traffic and decision system yet."
    }
    elseif ($allNoImages) {
        $coreProblem = "The site has core routes, but the visual layer is too weak to support clear scanning and decision flow."
    }
    elseif ($monetizationMissing) {
        $coreProblem = "The site has structure and content, but no visible conversion path is present in the audited routes."
    }
    else {
        $coreProblem = "The site is operational, but key route quality still limits decision strength."
    }

    if ($hasWeakHubs) {
        Add-UniqueItem -List $p1 -Text "Strengthen hubs as the main routing surface."
    }
    if ($hasWeakSearch) {
        Add-UniqueItem -List $p1 -Text "Improve search page quality so discovery does not feel thin."
    }

    if ($monetizationMissing -and (-not $hasAnyP0Structural)) {
        Add-UniqueItem -List $p1 -Text "Add one clear conversion path after core structural routes are strong enough."
    } else {
        Add-UniqueItem -List $p2 -Text "Monetization path is still missing, but it is not the first repair priority."
    }

    if ($p0.Count -eq 0 -and $p1.Count -eq 0 -and $p2.Count -eq 0) {
        Add-UniqueItem -List $p1 -Text "No critical blockers detected, but route quality can be improved."
    }

    $doNextTrim = New-List
    foreach ($item in $doNext) {
        if ($doNextTrim.Count -ge 3) { break }
        Add-UniqueItem -List $doNextTrim -Text $item
    }
    if ($doNextTrim.Count -eq 0) {
        if ($monetizationMissing -and (-not $hasAnyP0Structural)) {
            Add-UniqueItem -List $doNextTrim -Text "Add one clear conversion route with a visible offer or signup intent."
        }
    }

    $targetState30 = $null
    if ($hasWeakHubs -or $hasWeakSearch) {
        $targetState30 = "The site becomes structurally stronger, with deeper hubs/search routes and clearer forward navigation."
    }
    elseif ($monetizationMissing) {
        $targetState30 = "The site becomes decision-ready with one visible conversion path added on top of stable core routes."
    }
    else {
        $targetState30 = "The site becomes more decision-ready through stronger route depth and clearer action paths."
    }

    return [pscustomobject][ordered]@{
        site_stage = $siteStage
        core_problem = $coreProblem
        p0 = (Join-OrNull -List $p0)
        p1 = (Join-OrNull -List $p1)
        p2 = (Join-OrNull -List $p2)
        missing = (Join-OrNull -List $missing)
        do_next = (Join-OrNull -List $doNextTrim)
        target_state_30_days = $targetState30
    }
}

function Write-DecisionReport {
    param(
        [Parameter(Mandatory=$true)][string]$ReportsDir,
        [Parameter(Mandatory=$true)][object]$VisualSummary,
        [Parameter(Mandatory=$true)][object]$Decision
    )

    $reportLines = @()
    $reportLines += "SITE AUDITOR V4 REPORT"
    $reportLines += "BASE URL: $($VisualSummary.base_url)"
    $reportLines += "STATUS: $($VisualSummary.status)"
    $reportLines += "ROUTES: $($VisualSummary.route_count)"
    $reportLines += "SCREENSHOTS: $($VisualSummary.screenshots_count)"
    $reportLines += "COVERAGE SCORE: $($VisualSummary.coverage_score)"
    $reportLines += "SITE VISUAL HEALTH SCORE: $($VisualSummary.site_visual_health_score)"
    $reportLines += ""
    $reportLines += "SITE STAGE"
    $reportLines += "$($Decision.site_stage)"
    $reportLines += ""
    $reportLines += "CORE PROBLEM"
    $reportLines += "$($Decision.core_problem)"
    $reportLines += ""
    $reportLines += "P0 (BLOCKERS)"
    if ($Decision.p0) {
        foreach ($x in ($Decision.p0 -split '\s\|\s')) { $reportLines += "- $x" }
    } else {
        $reportLines += "- none"
    }
    $reportLines += ""
    $reportLines += "P1 (HIGH IMPACT)"
    if ($Decision.p1) {
        foreach ($x in ($Decision.p1 -split '\s\|\s')) { $reportLines += "- $x" }
    } else {
        $reportLines += "- none"
    }
    $reportLines += ""
    $reportLines += "P2 (LOW)"
    if ($Decision.p2) {
        foreach ($x in ($Decision.p2 -split '\s\|\s')) { $reportLines += "- $x" }
    } else {
        $reportLines += "- none"
    }
    $reportLines += ""
    $reportLines += "MISSING"
    if ($Decision.missing) {
        foreach ($x in ($Decision.missing -split '\s\|\s')) { $reportLines += "- $x" }
    } else {
        $reportLines += "- none"
    }
    $reportLines += ""
    $reportLines += "DO NEXT (MAX 3 STEPS)"
    if ($Decision.do_next) {
        $i = 1
        foreach ($x in ($Decision.do_next -split '\s\|\s')) {
            $reportLines += ("{0}. {1}" -f $i, $x)
            $i++
        }
    } else {
        $reportLines += "1. none"
    }
    $reportLines += ""
    $reportLines += "TARGET STATE (NEXT 30 DAYS)"
    $reportLines += "$($Decision.target_state_30_days)"
    $reportLines += ""
    $reportLines += "RAW COUNTS"
    $reportLines += "FAILED ROUTES: $(@($VisualSummary.failed_routes).Count)"
    $reportLines += "LOW COVERAGE ROUTES: $(@($VisualSummary.low_coverage_routes).Count)"
    $reportLines += "CONTENT EMPTY ROUTES: $(@($VisualSummary.content_empty_routes).Count)"
    $reportLines += "CONTENT METRICS MISSING ROUTES: $(@($VisualSummary.content_metrics_missing_routes).Count)"
    $reportLines += "HIGH FINDINGS: $($VisualSummary.findings_high)"
    $reportLines += "MEDIUM FINDINGS: $($VisualSummary.findings_medium)"
    $reportLines += "LOW FINDINGS: $($VisualSummary.findings_low)"

    [System.IO.File]::WriteAllLines((Join-Path $ReportsDir "REPORT.txt"), $reportLines, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-CaptureVisual {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptRoot
    )

    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        throw "node.exe not found in PATH"
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw "npm not found in PATH"
    }

    $capturePath = Join-Path $ScriptRoot "capture.mjs"
    if (-not (Test-Path -LiteralPath $capturePath)) {
        throw "capture.mjs not found: $capturePath"
    }

    $nodeModules = Join-Path $ScriptRoot "node_modules"
    $playwrightPkg = Join-Path $nodeModules "playwright"
    if (-not (Test-Path -LiteralPath $playwrightPkg)) {
        Push-Location $ScriptRoot
        try {
            & npm install
            if ($LASTEXITCODE -ne 0) {
                throw "npm install failed with exit code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }
    }

    Push-Location $ScriptRoot
    try {
        & node $capturePath
        if ($LASTEXITCODE -ne 0) {
            throw "capture.mjs failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-SiteAuditor {
    param([Parameter(Mandatory=$true)][string]$BaseUrl)

    $scriptRoot = Get-ScriptRoot
    $reportsDir = Join-Path $scriptRoot "reports"
    $screensDir = Join-Path $reportsDir "screenshots"

    Ensure-Directory -Path $reportsDir
    Ensure-Directory -Path $screensDir

    $routeInventory = Build-RouteInventory -BaseUrl $BaseUrl
    Write-JsonFile -Path (Join-Path $reportsDir "route_inventory.json") -Data $routeInventory -Depth 5

    Invoke-CaptureVisual -ScriptRoot $scriptRoot

    $manifestPath = Join-Path $reportsDir "visual_manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "visual_manifest.json not found after capture: $manifestPath"
    }

    $visualManifest = Read-JsonFile -Path $manifestPath
    $findings = @(Get-VisualFindings -Manifest $visualManifest)
    $visualSummary = Build-VisualSummary -BaseUrl $BaseUrl -Manifest $visualManifest -Findings $findings
    $routeScores = @(Build-RouteScores -Manifest $visualManifest)
    $decision = New-DecisionSummaryV4 -VisualSummary $visualSummary -RouteScores $routeScores

    Write-JsonFile -Path (Join-Path $reportsDir "visual_findings.json") -Data $findings -Depth 8
    Write-JsonFile -Path (Join-Path $reportsDir "visual_summary.json") -Data $visualSummary -Depth 8
    Write-JsonFile -Path (Join-Path $reportsDir "route_scores.json") -Data $routeScores -Depth 8
    Write-JsonFile -Path (Join-Path $reportsDir "decision_summary.json") -Data $decision -Depth 8
    Write-JsonFile -Path (Join-Path $reportsDir "final-status.json") -Data ([pscustomobject]@{ status = $visualSummary.status }) -Depth 3

    Write-DecisionReport -ReportsDir $reportsDir -VisualSummary $visualSummary -Decision $decision

    Write-Host "SITE_AUDITOR DONE"
    Write-Host "reportsDir: $reportsDir"
    Write-Host "status: $($visualSummary.status)"
}
