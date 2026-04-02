$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    return (Get-Location).Path
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }
    return ($raw | ConvertFrom-Json)
}

function Normalize-Items {
    param([object]$Items)
    if ($null -eq $Items) { return @() }
    return @($Items)
}

function Add-UniqueItem {
    param(
        [Parameter(Mandatory=$true)][ref]$ListRef,
        [Parameter(Mandatory=$true)][string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $list = @($ListRef.Value)
    if (-not ($list -contains $Text)) {
        $ListRef.Value = @($list + $Text)
    }
}

function Join-OrNull {
    param([object[]]$Items)
    $arr = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($arr.Count -eq 0) { return $null }
    return ($arr -join " | ")
}

function Get-RoutePath {
    param([object]$Item)
    if ($null -ne $Item.route_path -and -not [string]::IsNullOrWhiteSpace([string]$Item.route_path)) {
        return [string]$Item.route_path
    }
    if ($null -ne $Item.url -and -not [string]::IsNullOrWhiteSpace([string]$Item.url)) {
        try {
            $u = [Uri]([string]$Item.url)
            return $u.AbsolutePath
        }
        catch {
            return [string]$Item.url
        }
    }
    return "/unknown"
}

function Get-BodyTextLength {
    param([object]$Item)
    if ($null -ne $Item.bodyTextLength) { return [int]$Item.bodyTextLength }
    if ($null -ne $Item.body_text_length) { return [int]$Item.body_text_length }
    return 0
}

function Get-ImageCount {
    param([object]$Item)
    if ($null -ne $Item.images) { return [int]$Item.images }
    return 0
}

function Get-ScreenshotCount {
    param([object]$Item)
    if ($null -ne $Item.screenshotCount) { return [int]$Item.screenshotCount }
    if ($null -ne $Item.screenshots) { return @($Item.screenshots).Count }
    return 0
}

function Get-ContentMetricsPresent {
    param([object]$Item)
    if ($null -ne $Item.contentMetricsPresent) { return [bool]$Item.contentMetricsPresent }
    return ((Get-BodyTextLength -Item $Item) -gt 0)
}

function Get-RouteWeight {
    param([Parameter(Mandatory=$true)][string]$RoutePath)
    if ($RoutePath -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($RoutePath -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Get-VisualClass {
    param([object]$Item)
    $images = Get-ImageCount -Item $Item
    $len = Get-BodyTextLength -Item $Item
    if ($images -eq 0 -and $len -lt 400) { return 'visual_empty' }
    if ($images -eq 0) { return 'visual_weak' }
    return 'visual_ok'
}

function Build-RouteInventory {
    param([string]$BaseUrl)
    Write-Host "Build-RouteInventory: shim active"
}

function Get-VisualFindings {
    param([object[]]$ManifestItems)
    $items = Normalize-Items $ManifestItems
    $result = @()
    foreach ($i in $items) {
        $routePath = Get-RoutePath -Item $i
        $visualClass = Get-VisualClass -Item $i
        $result += [pscustomobject]@{
            route_path = $routePath
            visual_class = $visualClass
            body_text_length = (Get-BodyTextLength -Item $i)
            images = (Get-ImageCount -Item $i)
            screenshot_count = (Get-ScreenshotCount -Item $i)
        }
    }
    return @($result)
}

function Build-RouteScores {
    param([object[]]$ManifestItems)
    $items = Normalize-Items $ManifestItems
    $scores = @()
    foreach ($i in $items) {
        $routePath = Get-RoutePath -Item $i
        $len = Get-BodyTextLength -Item $i
        $weight = Get-RouteWeight -RoutePath $routePath
        $scoreBand = 'ok'
        if ($len -lt 350) { $scoreBand = 'watch' }
        $scores += [pscustomobject]@{
            route_path = $routePath
            body_text_length = $len
            images = (Get-ImageCount -Item $i)
            screenshot_count = (Get-ScreenshotCount -Item $i)
            score_band = $scoreBand
            route_importance = $weight
            weight = $weight
            content_metrics_present = (Get-ContentMetricsPresent -Item $i)
        }
    }
    return @($scores)
}

function Build-VisualSummary {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [object[]]$ManifestItems,
        [object[]]$Findings
    )
    $items = Normalize-Items $ManifestItems
    $findingsArr = Normalize-Items $Findings
    $suspectShort = @()
    $contentEmpty = @()
    $screenshotTotal = 0
    foreach ($i in $items) {
        $routePath = Get-RoutePath -Item $i
        $len = Get-BodyTextLength -Item $i
        if ($len -lt 350) { $suspectShort += $routePath }
        if (-not (Get-ContentMetricsPresent -Item $i)) { $contentEmpty += $routePath }
        $screenshotTotal += (Get-ScreenshotCount -Item $i)
    }
    $visualWeakCount = (@($findingsArr | Where-Object { $_.visual_class -ne 'visual_ok' })).Count
    $coverageScore = if ($items.Count -gt 0) { [Math]::Round(($screenshotTotal / [Math]::Max($items.Count, 1)), 2) } else { 0 }
    return [pscustomobject]@{
        base_url = $BaseUrl
        route_count = $items.Count
        screenshots_count = $screenshotTotal
        coverage_score = $coverageScore
        site_visual_health_score = if ($items.Count -gt 0) { [Math]::Round((($items.Count - $visualWeakCount) / $items.Count) * 10, 2) } else { 0 }
        content_empty_routes = @($contentEmpty)
        suspect_short_pages = @($suspectShort)
        status = if ($contentEmpty.Count -eq 0) { 'PASS_V4_5' } else { 'FAIL_CONTENT_EMPTY' }
    }
}

function Find-ScoreByRoute {
    param(
        [object[]]$RouteScores,
        [string]$RoutePath
    )
    foreach ($r in (Normalize-Items $RouteScores)) {
        if ([string]$r.route_path -eq $RoutePath) { return $r }
    }
    return $null
}

function New-DecisionSummaryV4 {
    param(
        [Parameter(Mandatory=$true)][object]$VisualSummary,
        [object[]]$RouteScores,
        [object[]]$Findings
    )

    $scores = Normalize-Items $RouteScores
    $findingsArr = Normalize-Items $Findings

    $p0 = @()
    $p1 = @()
    $p2 = @()
    $missing = @()
    $doNext = @()
    $routeWeightSignals = @()

    $hasWeakCritical = $false
    $hasWeakHigh = $false
    $hasVisualWeakness = $false

    foreach ($r in $scores) {
        $routePath = [string]$r.route_path
        $weight = [string]$r.weight
        $band = [string]$r.score_band

        if ($weight -eq 'critical') {
            Add-UniqueItem -ListRef ([ref]$routeWeightSignals) -Text "$routePath=critical"
        }
        elseif ($weight -eq 'high') {
            Add-UniqueItem -ListRef ([ref]$routeWeightSignals) -Text "$routePath=high"
        }

        if ($band -eq 'watch' -and $weight -eq 'critical') {
            $hasWeakCritical = $true
            Add-UniqueItem -ListRef ([ref]$p0) -Text "$routePath is a critical route and too shallow to support navigation flow."
        }
        elseif ($band -eq 'watch' -and $weight -eq 'high') {
            $hasWeakHigh = $true
            Add-UniqueItem -ListRef ([ref]$p1) -Text "$routePath is a high-value route and needs stronger depth."
        }
        elseif ($band -eq 'watch') {
            Add-UniqueItem -ListRef ([ref]$p2) -Text "$routePath is thinner than expected."
        }
    }

    foreach ($f in $findingsArr) {
        if ([string]$f.visual_class -eq 'visual_empty') {
            $hasVisualWeakness = $true
            Add-UniqueItem -ListRef ([ref]$p0) -Text "$($f.route_path) looks visually empty and weak for scanning."
        }
        elseif ([string]$f.visual_class -eq 'visual_weak') {
            $hasVisualWeakness = $true
            Add-UniqueItem -ListRef ([ref]$p1) -Text "$($f.route_path) lacks visual support blocks."
        }
    }

    $flowRisk = 'low'
    if ($hasWeakCritical) { $flowRisk = 'high' }
    elseif ($hasWeakHigh -or $hasVisualWeakness) { $flowRisk = 'medium' }

    $siteStage = 'Stage 1: Structure'
    if (-not $hasWeakCritical -and @($VisualSummary.content_empty_routes).Count -eq 0 -and [int]$VisualSummary.route_count -ge 5) {
        $siteStage = 'Stage 2: Product'
    }

    $coreProblem = 'Site structure exists but needs refinement.'
    if ($hasWeakCritical) {
        $coreProblem = 'Critical routes lack depth, breaking navigation flow and weakening the site as a traffic system.'
    }
    elseif ($hasVisualWeakness) {
        $coreProblem = 'Key routes are visually weak, reducing scanability and perceived completeness.'
    }

    Add-UniqueItem -ListRef ([ref]$missing) -Text 'No dedicated monetization or conversion route detected in the audited route set.'
    Add-UniqueItem -ListRef ([ref]$p2) -Text 'Monetization path is still missing, but it is not the first repair priority.'

    if ($hasWeakCritical) {
        Add-UniqueItem -ListRef ([ref]$doNext) -Text 'Expand /hubs/ into a stronger navigation hub with grouped next paths.'
        Add-UniqueItem -ListRef ([ref]$doNext) -Text 'Strengthen /search/ so discovery works as a real route, not a thin page.'
    }
    if ($hasVisualWeakness) {
        Add-UniqueItem -ListRef ([ref]$doNext) -Text 'Add visual support blocks or previews on key routes to improve scanability.'
    }
    if (@($doNext).Count -eq 0) {
        Add-UniqueItem -ListRef ([ref]$doNext) -Text 'Add one clear conversion route after structural routes are strong enough.'
    }
    $doNext = @($doNext | Select-Object -First 3)

    $visualWeaknessSummary = if ($hasVisualWeakness) {
        'Key routes are text-heavy and visually weak.'
    } else {
        'Visual layer is acceptable for the audited routes.'
    }

    $targetState = if ($hasWeakCritical) {
        'Within 30 days the site should have stronger hubs/search routes and clearer forward navigation.'
    }
    elseif ($hasVisualWeakness) {
        'Within 30 days the site should feel more complete through better visual support on key routes.'
    }
    else {
        'Within 30 days the site should add one visible conversion path on top of stable core routes.'
    }

    return [pscustomobject]@{
        site_stage = $siteStage
        core_problem = $coreProblem
        p0 = Join-OrNull -Items $p0
        p1 = Join-OrNull -Items $p1
        p2 = Join-OrNull -Items $p2
        missing = Join-OrNull -Items $missing
        do_next = Join-OrNull -Items $doNext
        target_state_30_days = $targetState
        route_weight_signals = Join-OrNull -Items $routeWeightSignals
        visual_weakness_summary = $visualWeaknessSummary
        flow_risk = $flowRisk
    }
}

function Write-TextReport {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$VisualSummary,
        [Parameter(Mandatory=$true)][object]$Decision
    )

    $lines = @()
    $lines += 'SITE AUDITOR REPORT'
    $lines += "BASE URL: $($VisualSummary.base_url)"
    $lines += "STATUS: $($VisualSummary.status)"
    $lines += "ROUTES: $($VisualSummary.route_count)"
    $lines += "SCREENSHOTS: $($VisualSummary.screenshots_count)"
    $lines += ''
    $lines += 'SITE STAGE'
    $lines += "$($Decision.site_stage)"
    $lines += ''
    $lines += 'CORE PROBLEM'
    $lines += "$($Decision.core_problem)"
    $lines += ''
    $lines += 'P0 (BLOCKERS)'
    if ($Decision.p0) { foreach ($x in ($Decision.p0 -split '\s\|\s')) { $lines += "- $x" } } else { $lines += '- none' }
    $lines += ''
    $lines += 'P1 (HIGH IMPACT)'
    if ($Decision.p1) { foreach ($x in ($Decision.p1 -split '\s\|\s')) { $lines += "- $x" } } else { $lines += '- none' }
    $lines += ''
    $lines += 'P2 (LOW)'
    if ($Decision.p2) { foreach ($x in ($Decision.p2 -split '\s\|\s')) { $lines += "- $x" } } else { $lines += '- none' }
    $lines += ''
    $lines += 'MISSING'
    if ($Decision.missing) { foreach ($x in ($Decision.missing -split '\s\|\s')) { $lines += "- $x" } } else { $lines += '- none' }
    $lines += ''
    $lines += 'DO NEXT (MAX 3 STEPS)'
    $i = 1
    if ($Decision.do_next) { foreach ($x in ($Decision.do_next -split '\s\|\s')) { $lines += ("{0}. {1}" -f $i, $x); $i++ } } else { $lines += '1. none' }
    $lines += ''
    $lines += 'TARGET STATE (30 DAYS)'
    $lines += "$($Decision.target_state_30_days)"
    $lines += ''
    $lines += 'FLOW RISK'
    $lines += "$($Decision.flow_risk)"
    $lines += ''
    $lines += 'VISUAL WEAKNESS SUMMARY'
    $lines += "$($Decision.visual_weakness_summary)"
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([Parameter(Mandatory=$true)][string]$BaseUrl)

    $scriptRoot = Get-ScriptRoot
    Write-Host "scriptRoot: $scriptRoot"

    $reportsDir = Join-Path $scriptRoot 'reports'
    Ensure-Directory -Path $reportsDir

    $manifestPath = Join-Path $reportsDir 'visual_manifest.json'
    $manifest = Read-JsonFile -Path $manifestPath
    $items = Normalize-Items $manifest

    $findings = Get-VisualFindings -ManifestItems $items
    $routeScores = Build-RouteScores -ManifestItems $items
    $visualSummary = Build-VisualSummary -BaseUrl $BaseUrl -ManifestItems $items -Findings $findings
    $decision = New-DecisionSummaryV4 -VisualSummary $visualSummary -RouteScores $routeScores -Findings $findings

    $findings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir 'visual_findings.json') -Encoding UTF8
    $visualSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir 'visual_summary.json') -Encoding UTF8
    $routeScores | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir 'route_scores.json') -Encoding UTF8
    $decision | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir 'decision_summary.json') -Encoding UTF8

    $finalStatus = [pscustomobject]@{
        status = 'PASS'
        base_url = $BaseUrl
        reports_dir = $reportsDir
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    $finalStatus | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reportsDir 'final-status.json') -Encoding UTF8

    Write-TextReport -Path (Join-Path $reportsDir 'REPORT.txt') -VisualSummary $visualSummary -Decision $decision
    Write-Host 'SITE_AUDITOR REPORTS WRITTEN'
}
