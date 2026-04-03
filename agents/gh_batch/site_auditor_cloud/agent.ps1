$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Build-RouteInventory {
    param([string]$BaseUrl)
    Write-Host "Build-RouteInventory: shim active"
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
    return @($Items)
}

function Get-RoutePathFromItem {
    param([object]$Item)
    if ($null -ne $Item.route_path -and -not [string]::IsNullOrWhiteSpace([string]$Item.route_path)) {
        return [string]$Item.route_path
    }
    if ($null -ne $Item.url -and -not [string]::IsNullOrWhiteSpace([string]$Item.url)) {
        try {
            $u = [uri]([string]$Item.url)
            $p = $u.AbsolutePath
            if ([string]::IsNullOrWhiteSpace($p)) { return "/" }
            return $p
        } catch {
            return [string]$Item.url
        }
    }
    return ""
}

function Get-IntValue {
    param([object]$Value, [int]$Default = 0)
    if ($null -eq $Value) { return $Default }
    try { return [int]$Value } catch { return $Default }
}

function Get-RouteWeight {
    param([string]$Path)
    switch ($Path) {
        "/"            { return "critical" }
        "/hubs/"       { return "critical" }
        "/search/"     { return "critical" }
        "/tools/"      { return "high" }
        "/start-here/" { return "high" }
        default        { return "normal" }
    }
}

function Get-VisualClass {
    param(
        [int]$Images,
        [int]$BodyTextLength
    )
    if ($Images -eq 0 -and $BodyTextLength -lt 350) { return "visual_empty" }
    if ($Images -eq 0) { return "visual_weak" }
    return "visual_ok"
}

function Get-VisualFindings {
    param([object[]]$ManifestItems)

    $items = Normalize-Items $ManifestItems
    $result = @()

    foreach ($i in $items) {
        $routePath = Get-RoutePathFromItem -Item $i
        $images = Get-IntValue -Value $i.images
        $bodyTextLength = Get-IntValue -Value $i.bodyTextLength
        $links = Get-IntValue -Value $i.links
        $screenshotCount = Get-IntValue -Value $i.screenshotCount
        $contentMetricsPresent = $false
        if ($null -ne $i.contentMetricsPresent) { $contentMetricsPresent = [bool]$i.contentMetricsPresent }

        $visualClass = Get-VisualClass -Images $images -BodyTextLength $bodyTextLength
        $scanability = "ok"
        if ($visualClass -eq "visual_empty") { $scanability = "low" }
        elseif ($visualClass -eq "visual_weak") { $scanability = "weak" }

        $result += [pscustomobject]@{
            route_path              = $routePath
            url                     = $i.url
            body_text_length        = $bodyTextLength
            links                   = $links
            images                  = $images
            screenshot_count        = $screenshotCount
            content_metrics_present = $contentMetricsPresent
            visual_class            = $visualClass
            scanability             = $scanability
        }
    }

    return @($result)
}

function Build-RouteScores {
    param([object[]]$ManifestItems)

    $items = Normalize-Items $ManifestItems
    $scores = @()

    foreach ($i in $items) {
        $routePath = Get-RoutePathFromItem -Item $i
        $length = Get-IntValue -Value $i.bodyTextLength
        $images = Get-IntValue -Value $i.images
        $weight = Get-RouteWeight -Path $routePath

        $scoreBand = "ok"
        if ($length -lt 350) {
            $scoreBand = "watch"
        }
        elseif ($length -lt 700) {
            $scoreBand = "thin"
        }

        $importance = "normal"
        if ($weight -eq "critical") { $importance = "high" }
        elseif ($weight -eq "high") { $importance = "medium" }

        $scores += [pscustomobject]@{
            route_path       = $routePath
            route_importance = $importance
            route_weight     = $weight
            score_band       = $scoreBand
            body_text_length = $length
            images           = $images
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
    $fs = Normalize-Items $Findings

    $routeCount = $items.Count
    $screenshotsCount = 0
    $contentEmptyRoutes = @()
    $suspectShortPages = @()
    $visualEmptyCount = 0
    $visualWeakCount = 0

    foreach ($i in $items) {
        $screenshotsCount += (Get-IntValue -Value $i.screenshotCount)
    }

    foreach ($f in $fs) {
        if (-not $f.content_metrics_present) {
            $contentEmptyRoutes += $f.route_path
        }
        if ((Get-IntValue -Value $f.body_text_length) -lt 350) {
            $suspectShortPages += $f.route_path
        }
        if ($f.visual_class -eq "visual_empty") { $visualEmptyCount++ }
        elseif ($f.visual_class -eq "visual_weak") { $visualWeakCount++ }
    }

    $coverageScore = 0
    if ($routeCount -gt 0) {
        $coverageScore = [math]::Round(($screenshotsCount / $routeCount), 2)
    }

    $health = "good"
    if ($visualEmptyCount -gt 0 -or $contentEmptyRoutes.Count -gt 0) {
        $health = "weak"
    } elseif ($visualWeakCount -gt 0) {
        $health = "mixed"
    }

    return [pscustomobject]@{
        base_url                 = $BaseUrl
        status                   = "PASS_V4_6"
        route_count              = $routeCount
        screenshots_count        = $screenshotsCount
        coverage_score           = $coverageScore
        site_visual_health_score = $health
        content_empty_routes     = @($contentEmptyRoutes)
        suspect_short_pages      = @($suspectShortPages)
        visual_empty_count       = $visualEmptyCount
        visual_weak_count        = $visualWeakCount
    }
}

function Add-UniqueText {
    param(
        [ref]$Bucket,
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $arr = @($Bucket.Value)
    if (-not ($arr -contains $Text)) {
        $Bucket.Value = @($arr + $Text)
    }
}

function Select-TopItems {
    param(
        [object[]]$Items,
        [int]$Limit = 4
    )
    $items = Normalize-Items $Items
    if ($items.Count -le $Limit) { return @($items) }
    return @($items | Select-Object -First $Limit)
}

function New-DecisionSummaryV46 {
    param(
        [Parameter(Mandatory=$true)][object]$VisualSummary,
        [Parameter(Mandatory=$true)][object[]]$RouteScores,
        [Parameter(Mandatory=$true)][object[]]$Findings
    )

    $scores = Normalize-Items $RouteScores
    $findings = Normalize-Items $Findings

    $p0 = @()
    $p1 = @()
    $p2 = @()
    $missing = @()
    $doNext = @()

    $criticalIssues = @()
    $highIssues = @()
    $visualEmptyRoutes = @()
    $visualWeakRoutes = @()

    foreach ($r in $scores) {
        if ($r.route_weight -eq "critical" -and ($r.score_band -eq "watch" -or $r.score_band -eq "thin")) {
            $criticalIssues += $r
        } elseif ($r.route_weight -eq "high" -and $r.score_band -eq "watch") {
            $highIssues += $r
        }
    }

    foreach ($f in $findings) {
        if ($f.visual_class -eq "visual_empty") { $visualEmptyRoutes += $f }
        elseif ($f.visual_class -eq "visual_weak") { $visualWeakRoutes += $f }
    }

    $flowRisk = "low"
    if ($criticalIssues.Count -ge 2) { $flowRisk = "high" }
    elseif ($criticalIssues.Count -eq 1 -or $visualEmptyRoutes.Count -gt 0) { $flowRisk = "medium" }

    $siteStage = "Stage 2: Product"
    if ($criticalIssues.Count -gt 0 -or $visualEmptyRoutes.Count -gt 0) {
        $siteStage = "Stage 1: Structure"
    } elseif ($visualWeakRoutes.Count -gt 0) {
        $siteStage = "Stage 1 / early Stage 2"
    }

    $coreProblem = "The site has structure, but route quality still limits decision flow."
    if ($criticalIssues.Count -gt 0) {
        $coreProblem = "Critical discovery and routing routes lack enough depth, weakening the site's navigation flow."
    } elseif ($visualEmptyRoutes.Count -gt 0) {
        $coreProblem = "Key routes look visually empty, reducing scanability and perceived completeness."
    } elseif ($visualWeakRoutes.Count -gt 0) {
        $coreProblem = "The visual layer is weak across key routes, which reduces clarity and confidence."
    }

    foreach ($r in (Select-TopItems -Items $criticalIssues -Limit 3)) {
        $msg = "{0} is a critical route and is too shallow to support navigation flow." -f $r.route_path
        Add-UniqueText -Bucket ([ref]$p0) -Text $msg
    }

    if ($visualEmptyRoutes.Count -gt 0) {
        Add-UniqueText -Bucket ([ref]$p0) -Text "Some key routes appear visually empty, which weakens scanability."
    } elseif ($visualWeakRoutes.Count -gt 1) {
        Add-UniqueText -Bucket ([ref]$p1) -Text "Key routes are text-heavy and visually weak."
    }

    foreach ($r in (Select-TopItems -Items $highIssues -Limit 2)) {
        $msg = "{0} needs more depth to support the site's decision flow." -f $r.route_path
        Add-UniqueText -Bucket ([ref]$p1) -Text $msg
    }

    if ($criticalIssues.Count -gt 0) {
        Add-UniqueText -Bucket ([ref]$p1) -Text "Strengthen routing surfaces before expanding monetization."
    }

    Add-UniqueText -Bucket ([ref]$missing) -Text "No dedicated monetization or conversion route detected in the audited route set."
    Add-UniqueText -Bucket ([ref]$p2) -Text "Monetization is still missing, but it is not the first repair priority."

    $routeWeightSignals = @()
    foreach ($r in (Select-TopItems -Items ($scores | Where-Object { $_.route_weight -ne "normal" }) -Limit 5)) {
        $routeWeightSignals += ("{0}:{1}:{2}" -f $r.route_path, $r.route_weight, $r.score_band)
    }

    $visualWeaknessSummary = "Visual layer is acceptable."
    if ($visualEmptyRoutes.Count -gt 0) {
        $paths = @($visualEmptyRoutes | ForEach-Object { $_.route_path })
        $visualWeaknessSummary = "Routes appear visually empty: " + ($paths -join ", ")
    } elseif ($visualWeakRoutes.Count -gt 0) {
        $paths = @($visualWeakRoutes | ForEach-Object { $_.route_path })
        $visualWeaknessSummary = "Routes are visually weak: " + ($paths -join ", ")
    }

    if ($criticalIssues | Where-Object { $_.route_path -eq "/hubs/" }) {
        Add-UniqueText -Bucket ([ref]$doNext) -Text "Expand /hubs/ into category-level navigation with clearer forward paths."
    }
    if ($criticalIssues | Where-Object { $_.route_path -eq "/search/" }) {
        Add-UniqueText -Bucket ([ref]$doNext) -Text "Strengthen /search/ so it works as a real discovery route, not a thin utility page."
    }
    if ($visualEmptyRoutes.Count -gt 0 -or $visualWeakRoutes.Count -gt 0) {
        Add-UniqueText -Bucket ([ref]$doNext) -Text "Add visual support blocks or previews on key routes to improve scanability."
    }
    if ($doNext.Count -eq 0) {
        Add-UniqueText -Bucket ([ref]$doNext) -Text "Tighten key route quality before adding new growth surfaces."
    }

    $doNext = @(Select-TopItems -Items $doNext -Limit 3)
    $p0 = @(Select-TopItems -Items $p0 -Limit 4)
    $p1 = @(Select-TopItems -Items $p1 -Limit 4)
    $p2 = @(Select-TopItems -Items $p2 -Limit 3)
    $missing = @(Select-TopItems -Items $missing -Limit 3)

    $targetState30 = "The site has deeper hubs/search routes, stronger scanability on key pages, and clearer next-step navigation."

    return [pscustomobject]@{
        site_stage               = $siteStage
        core_problem             = $coreProblem
        p0                       = @($p0)
        p1                       = @($p1)
        p2                       = @($p2)
        missing                  = @($missing)
        do_next                  = @($doNext)
        target_state_30_days     = $targetState30
        route_weight_signals     = @($routeWeightSignals)
        visual_weakness_summary  = $visualWeaknessSummary
        flow_risk                = $flowRisk
    }
}

function Write-ReportText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$VisualSummary,
        [Parameter(Mandatory=$true)][object]$Decision
    )

    $lines = @()
    $lines += "SITE AUDITOR REPORT"
    $lines += "BASE URL: $($VisualSummary.base_url)"
    $lines += "STATUS: $($VisualSummary.status)"
    $lines += "ROUTES: $($VisualSummary.route_count)"
    $lines += "SCREENSHOTS: $($VisualSummary.screenshots_count)"
    $lines += "COVERAGE SCORE: $($VisualSummary.coverage_score)"
    $lines += "FLOW RISK: $($Decision.flow_risk)"
    $lines += ""
    $lines += "SITE STAGE"
    $lines += "$($Decision.site_stage)"
    $lines += ""
    $lines += "CORE PROBLEM"
    $lines += "$($Decision.core_problem)"
    $lines += ""
    $lines += "VISUAL WEAKNESS SUMMARY"
    $lines += "$($Decision.visual_weakness_summary)"
    $lines += ""
    $lines += "P0 (BLOCKERS)"
    if (@($Decision.p0).Count -gt 0) { foreach ($x in @($Decision.p0)) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "P1 (HIGH IMPACT)"
    if (@($Decision.p1).Count -gt 0) { foreach ($x in @($Decision.p1)) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "P2 (LOW)"
    if (@($Decision.p2).Count -gt 0) { foreach ($x in @($Decision.p2)) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "MISSING"
    if (@($Decision.missing).Count -gt 0) { foreach ($x in @($Decision.missing)) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "DO NEXT (MAX 3 STEPS)"
    $idx = 1
    foreach ($x in @($Decision.do_next)) {
        $lines += ("{0}. {1}" -f $idx, $x)
        $idx++
    }
    if ($idx -eq 1) { $lines += "1. none" }
    $lines += ""
    $lines += "TARGET STATE (NEXT 30 DAYS)"
    $lines += "$($Decision.target_state_30_days)"
    $lines += ""
    $lines += "ROUTE WEIGHT SIGNALS"
    if (@($Decision.route_weight_signals).Count -gt 0) { foreach ($x in @($Decision.route_weight_signals)) { $lines += "- $x" } } else { $lines += "- none" }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([Parameter(Mandatory=$true)][string]$BaseUrl)

    $scriptRoot = Get-ScriptRoot
    Write-Host "scriptRoot: $scriptRoot"

    $reportsDir = Join-Path $scriptRoot "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir | Out-Null
    }

    $manifestPath = Join-Path $reportsDir "visual_manifest.json"
    $manifest = Read-JsonFile -Path $manifestPath
    $items = Normalize-Items $manifest

    $findings = Get-VisualFindings -ManifestItems $items
    $summary = Build-VisualSummary -BaseUrl $BaseUrl -ManifestItems $items -Findings $findings
    $routeScores = Build-RouteScores -ManifestItems $items
    $decision = New-DecisionSummaryV46 -VisualSummary $summary -RouteScores $routeScores -Findings $findings

    $findings | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $reportsDir "visual_findings.json") -Encoding UTF8
    $summary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $reportsDir "visual_summary.json") -Encoding UTF8
    $routeScores | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $reportsDir "route_scores.json") -Encoding UTF8
    $decision | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $reportsDir "decision_summary.json") -Encoding UTF8

    $finalStatus = [pscustomobject]@{
        status     = "PASS"
        base_url   = $BaseUrl
        reports_dir= $reportsDir
        manifest   = $manifestPath
        route_count= @($items).Count
    }
    $finalStatus | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $reportsDir "final-status.json") -Encoding UTF8

    Write-ReportText -Path (Join-Path $reportsDir "REPORT.txt") -VisualSummary $summary -Decision $decision

    Write-Host "SITE_AUDITOR DONE"
}