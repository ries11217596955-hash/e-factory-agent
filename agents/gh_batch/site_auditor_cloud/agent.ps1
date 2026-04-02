$ErrorActionPreference = "Stop"

function Build-RouteInventory {
    param([string]$BaseUrl)
    Write-Host "Build-RouteInventory: skipped (handled by capture layer)"
}

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Normalize-Items {
    param([object]$Items)
    if ($null -eq $Items) { return @() }
    return @($Items)
}

function Get-IntValue {
    param([object]$Value, [int]$Default = 0)
    if ($null -eq $Value) { return $Default }
    try { return [int]$Value } catch { return $Default }
}

function Get-RoutePath {
    param([object]$Item)
    foreach ($name in @('route_path','path','url_path','route')) {
        if ($null -ne $Item.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Item.$name)) {
            return [string]$Item.$name
        }
    }
    foreach ($name in @('url','page_url')) {
        if ($null -ne $Item.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Item.$name)) {
            try {
                $u = [uri][string]$Item.$name
                return $u.AbsolutePath
            }
            catch {
                return [string]$Item.$name
            }
        }
    }
    return "unknown"
}

function Get-BodyTextLength {
    param([object]$Item)
    foreach ($name in @('bodyTextLength','body_text_length','textLength','content_length')) {
        if ($null -ne $Item.PSObject.Properties[$name]) {
            return Get-IntValue -Value $Item.$name -Default 0
        }
    }
    return 0
}

function Get-ImagesCount {
    param([object]$Item)
    foreach ($name in @('images','imageCount','images_count')) {
        if ($null -ne $Item.PSObject.Properties[$name]) {
            return Get-IntValue -Value $Item.$name -Default 0
        }
    }
    return 0
}

function Get-ScreenshotCount {
    param([object]$Item)
    foreach ($name in @('screenshotCount','screenshots','screenshots_count')) {
        if ($null -ne $Item.PSObject.Properties[$name]) {
            return Get-IntValue -Value $Item.$name -Default 0
        }
    }
    return 0
}

function Get-RouteWeight {
    param([string]$Path)
    if ($Path -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($Path -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Get-VisualFindings {
    param([object[]]$ManifestItems)

    $items = Normalize-Items $ManifestItems
    $result = @()

    foreach ($i in $items) {
        $routePath = Get-RoutePath -Item $i
        $images = Get-ImagesCount -Item $i
        $len = Get-BodyTextLength -Item $i

        $visualClass = 'visual_ok'
        if ($images -eq 0 -and $len -lt 400) {
            $visualClass = 'visual_empty'
        }
        elseif ($images -eq 0) {
            $visualClass = 'visual_weak'
        }

        $result += [pscustomobject]@{
            route_path   = $routePath
            images       = $images
            body_length  = $len
            visual_class = $visualClass
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
        $images = Get-ImagesCount -Item $i
        $weight = Get-RouteWeight -Path $routePath

        $band = 'ok'
        if ($len -lt 350) {
            $band = 'watch'
        }

        $scores += [pscustomobject]@{
            route_path        = $routePath
            score_band        = $band
            weight            = $weight
            route_importance  = $weight
            body_text_length  = $len
            images            = $images
        }
    }

    return @($scores)
}

function Build-VisualSummary {
    param(
        [string]$BaseUrl,
        [object[]]$ManifestItems,
        [object[]]$Findings
    )

    $items = Normalize-Items $ManifestItems
    $findingsNorm = Normalize-Items $Findings
    $count = @($items).Count
    $screenshotsCount = 0
    $contentEmptyRoutes = @()
    $suspectShortPages = @()
    $visualWeakCount = 0

    foreach ($i in $items) {
        $screenshotsCount += Get-ScreenshotCount -Item $i
        $routePath = Get-RoutePath -Item $i
        $len = Get-BodyTextLength -Item $i
        if ($len -eq 0) { $contentEmptyRoutes += $routePath }
        if ($len -gt 0 -and $len -lt 350) { $suspectShortPages += $routePath }
    }

    foreach ($f in $findingsNorm) {
        if ($f.visual_class -ne 'visual_ok') { $visualWeakCount++ }
    }

    return [pscustomobject]@{
        base_url                = $BaseUrl
        route_count             = $count
        screenshots_count       = $screenshotsCount
        coverage_score          = $screenshotsCount
        content_empty_routes    = @($contentEmptyRoutes)
        suspect_short_pages     = @($suspectShortPages)
        site_visual_health_score= [math]::Max(0, $count - $visualWeakCount)
        status                  = 'PASS_V45'
    }
}

function New-DecisionSummaryV4 {
    param(
        [object]$VisualSummary,
        [object[]]$RouteScores,
        [object[]]$Findings
    )

    $routeScoresNorm = Normalize-Items $RouteScores
    $findingsNorm = Normalize-Items $Findings

    $p0 = @()
    $p1 = @()
    $p2 = @()
    $missing = @()
    $doNext = @()
    $routeWeightSignals = @()
    $visualWeaknessSummary = @()

    $hasWeakCritical = $false
    $hasWeakHigh = $false
    $flowRisk = 'low'

    foreach ($r in $routeScoresNorm) {
        $signal = "$($r.route_path)=$($r.weight)/$($r.score_band)"
        $routeWeightSignals += $signal

        if ($r.score_band -eq 'watch' -and $r.weight -eq 'critical') {
            $hasWeakCritical = $true
            $p0 += "$($r.route_path) is a critical route and too shallow to support navigation flow."
        }
        elseif ($r.score_band -eq 'watch' -and $r.weight -eq 'high') {
            $hasWeakHigh = $true
            $p1 += "$($r.route_path) is important but not strong enough yet."
        }
        elseif ($r.score_band -eq 'watch') {
            $p2 += "$($r.route_path) is thin and should be strengthened later."
        }
    }

    foreach ($f in $findingsNorm) {
        if ($f.visual_class -eq 'visual_empty') {
            $visualWeaknessSummary += "$($f.route_path)=visual_empty"
        }
        elseif ($f.visual_class -eq 'visual_weak') {
            $visualWeaknessSummary += "$($f.route_path)=visual_weak"
        }
    }

    if (@($visualWeaknessSummary).Count -gt 0) {
        $p0 += 'Key routes are visually weak and scan poorly.'
        $missing += 'No strong visual support blocks detected across weak routes.'
    }

    if ($hasWeakCritical) {
        $flowRisk = 'high'
    }
    elseif ($hasWeakHigh) {
        $flowRisk = 'medium'
    }

    $stage = 'Stage 1: Structure'
    if (-not $hasWeakCritical -and @($VisualSummary.content_empty_routes).Count -eq 0) {
        $stage = 'Stage 2: Product'
    }

    $core = 'Site structure exists but needs refinement.'
    if ($hasWeakCritical) {
        $core = 'Critical routes lack depth, breaking navigation and discovery flow.'
    }
    elseif (@($visualWeaknessSummary).Count -gt 0) {
        $core = 'Key routes are visually weak, reducing scanability and perceived completeness.'
    }

    if ($hasWeakCritical) {
        $doNext += 'Expand /hubs/ into a structured navigation surface with clear route groups.'
        $doNext += 'Improve /search/ so it works as a discovery route, not a thin placeholder.'
    }
    if (@($visualWeaknessSummary).Count -gt 0) {
        $doNext += 'Add visual support blocks or previews on key routes to improve scanability.'
    }
    if (@($doNext).Count -eq 0) {
        $doNext += 'Strengthen the highest-value routes first.'
    }
    if (@($doNext).Count -gt 3) {
        $doNext = @($doNext)[0..2]
    }

    $targetState = 'The site has stronger hubs/search routes, clearer forward navigation, and visible support blocks on key pages.'

    return [pscustomobject]@{
        site_stage              = $stage
        core_problem            = $core
        p0                      = (@($p0) -join ' | ')
        p1                      = (@($p1) -join ' | ')
        p2                      = (@($p2) -join ' | ')
        missing                 = (@($missing) -join ' | ')
        do_next                 = (@($doNext) -join ' | ')
        target_state_30_days    = $targetState
        route_weight_signals    = (@($routeWeightSignals) -join ' | ')
        visual_weakness_summary = (@($visualWeaknessSummary) -join ' | ')
        flow_risk               = $flowRisk
    }
}

function Write-ReportText {
    param(
        [string]$ReportsDir,
        [object]$VisualSummary,
        [object]$Decision
    )

    $reportLines = @()
    $reportLines += 'SITE AUDITOR REPORT'
    $reportLines += "BASE URL: $($VisualSummary.base_url)"
    $reportLines += "STATUS: $($VisualSummary.status)"
    $reportLines += "ROUTES: $($VisualSummary.route_count)"
    $reportLines += "SCREENSHOTS: $($VisualSummary.screenshots_count)"
    $reportLines += ''
    $reportLines += 'SITE STAGE'
    $reportLines += "$($Decision.site_stage)"
    $reportLines += ''
    $reportLines += 'CORE PROBLEM'
    $reportLines += "$($Decision.core_problem)"
    $reportLines += ''
    $reportLines += 'P0 (BLOCKERS)'
    if ([string]::IsNullOrWhiteSpace([string]$Decision.p0)) { $reportLines += '- none' } else { foreach ($x in ($Decision.p0 -split '\s\|\s')) { $reportLines += "- $x" } }
    $reportLines += ''
    $reportLines += 'P1 (HIGH IMPACT)'
    if ([string]::IsNullOrWhiteSpace([string]$Decision.p1)) { $reportLines += '- none' } else { foreach ($x in ($Decision.p1 -split '\s\|\s')) { $reportLines += "- $x" } }
    $reportLines += ''
    $reportLines += 'P2 (LOW)'
    if ([string]::IsNullOrWhiteSpace([string]$Decision.p2)) { $reportLines += '- none' } else { foreach ($x in ($Decision.p2 -split '\s\|\s')) { $reportLines += "- $x" } }
    $reportLines += ''
    $reportLines += 'MISSING'
    if ([string]::IsNullOrWhiteSpace([string]$Decision.missing)) { $reportLines += '- none' } else { foreach ($x in ($Decision.missing -split '\s\|\s')) { $reportLines += "- $x" } }
    $reportLines += ''
    $reportLines += 'DO NEXT (MAX 3 STEPS)'
    $stepIndex = 1
    foreach ($x in ($Decision.do_next -split '\s\|\s')) {
        if (-not [string]::IsNullOrWhiteSpace($x)) {
            $reportLines += ("{0}. {1}" -f $stepIndex, $x)
            $stepIndex++
        }
    }
    $reportLines += ''
    $reportLines += 'TARGET STATE (NEXT 30 DAYS)'
    $reportLines += "$($Decision.target_state_30_days)"

    Set-Content -Path (Join-Path $ReportsDir 'REPORT.txt') -Value $reportLines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $scriptRoot = Get-ScriptRoot
    Write-Host "scriptRoot: $scriptRoot"

    $reportsDir = Join-Path $scriptRoot 'reports'
    if (-not (Test-Path $reportsDir)) {
        $null = New-Item -ItemType Directory -Path $reportsDir -Force
    }

    $manifestPath = Join-Path $scriptRoot 'visual_manifest.json'
    $visualManifest = Read-JsonFile -Path $manifestPath
    $items = Normalize-Items $visualManifest

    $findings = Get-VisualFindings -ManifestItems $items
    $visualSummary = Build-VisualSummary -BaseUrl $BaseUrl -ManifestItems $items -Findings $findings
    $routeScores = Build-RouteScores -ManifestItems $items
    $decision = New-DecisionSummaryV4 -VisualSummary $visualSummary -RouteScores $routeScores -Findings $findings

    $findings | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $reportsDir 'visual_findings.json') -Encoding UTF8
    $visualSummary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $reportsDir 'visual_summary.json') -Encoding UTF8
    $routeScores | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $reportsDir 'route_scores.json') -Encoding UTF8
    $decision | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $reportsDir 'decision_summary.json') -Encoding UTF8

    Write-ReportText -ReportsDir $reportsDir -VisualSummary $visualSummary -Decision $decision

    Write-Host 'SITE_AUDITOR: reports written successfully'
}
