# =========================
# V4 DECISION ENGINE PATCH
# PS5.1-safe
# Replace old decision-summary builder with this block
# =========================

function New-DecisionSummaryV4 {
    param(
        [Parameter(Mandatory=$true)] [object]$VisualSummary,
        [Parameter(Mandatory=$true)] [object[]]$RouteScores
    )

    function New-List {
        return New-Object System.Collections.Generic.List[string]
    }

    function Add-UniqueItem {
        param(
            [Parameter(Mandatory=$true)] [System.Collections.Generic.List[string]]$List,
            [Parameter(Mandatory=$true)] [string]$Text
        )
        if ([string]::IsNullOrWhiteSpace($Text)) { return }
        if (-not $List.Contains($Text)) {
            $null = $List.Add($Text)
        }
    }

    function Join-OrNull {
        param(
            [Parameter(Mandatory=$true)] [System.Collections.Generic.List[string]]$List,
            [string]$Sep = " | "
        )
        if ($List.Count -eq 0) { return $null }
        return ($List.ToArray() -join $Sep)
    }

    function Is-KeyRoute {
        param([string]$RoutePath)
        $key = @("/", "/hubs/", "/search/", "/tools/", "/start-here/")
        return ($key -contains $RoutePath)
    }

    function Is-HighValueRoute {
        param([object]$Route)
        if ($Route.route_importance -eq "high") { return $true }
        if (Is-KeyRoute -RoutePath $Route.route_path) { return $true }
        return $false
    }

    function Is-ShallowRoute {
        param([object]$Route)

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
        param([object[]]$Routes)

        foreach ($r in $Routes) {
            $img = 0
            if ($null -ne $r.images) { $img = [int]$r.images }
            if ($img -gt 0) { return $false }
        }
        return $true
    }

    function Find-Route {
        param(
            [object[]]$Routes,
            [string]$RoutePath
        )
        foreach ($r in $Routes) {
            if ([string]$r.route_path -eq $RoutePath) { return $r }
        }
        return $null
    }

    $p0      = New-List
    $p1      = New-List
    $p2      = New-List
    $missing = New-List
    $doNext  = New-List

    $routeCount = 0
    if ($null -ne $VisualSummary.route_count) {
        $routeCount = [int]$VisualSummary.route_count
    }

    $screenshotsCount = 0
    if ($null -ne $VisualSummary.screenshots_count) {
        $screenshotsCount = [int]$VisualSummary.screenshots_count
    }

    $contentEmptyCount = 0
    if ($null -ne $VisualSummary.content_empty_routes) {
        $contentEmptyCount = @($VisualSummary.content_empty_routes).Count
    }

    $shortRoutes = @()
    if ($null -ne $VisualSummary.suspect_short_pages) {
        $shortRoutes = @($VisualSummary.suspect_short_pages)
    }

    $hubsRoute   = Find-Route -Routes $RouteScores -RoutePath "/hubs/"
    $searchRoute = Find-Route -Routes $RouteScores -RoutePath "/search/"
    $toolsRoute  = Find-Route -Routes $RouteScores -RoutePath "/tools/"
    $homeRoute   = Find-Route -Routes $RouteScores -RoutePath "/"
    $startRoute  = Find-Route -Routes $RouteScores -RoutePath "/start-here/"

    $hasWeakHubs   = $false
    $hasWeakSearch = $false
    $hasWeakTools  = $false
    $hasAnyP0Structural = $false
    $allNoImages = Has-VisualWeakness -Routes $RouteScores

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
            $hasWeakTools = $true
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

    # -------------------------
    # STAGE DETECTION
    # -------------------------
    $siteStage = "Stage 1: Structure"

    if (-not $hasAnyP0Structural -and $contentEmptyCount -eq 0 -and $routeCount -ge 5) {
        $siteStage = "Stage 2: Product"
    }

    if ($hasWeakHubs -or $hasWeakSearch) {
        $siteStage = "Stage 1: Structure"
    }

    if ((-not $hasAnyP0Structural) -and ($monetizationMissing)) {
        # Do not upgrade stage just because content exists
        if ($siteStage -eq "Stage 2: Product") {
            $siteStage = "Stage 2: Product"
        }
    }

    # -------------------------
    # CORE PROBLEM
    # -------------------------
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

    # -------------------------
    # PRIORITIES
    # -------------------------
    if ($hasWeakHubs) {
        Add-UniqueItem -List $p1 -Text "Strengthen hubs as the main routing surface."
    }

    if ($hasWeakSearch) {
        Add-UniqueItem -List $p1 -Text "Improve search page quality so discovery does not feel thin."
    }

    if ($monetizationMissing -and (-not $hasAnyP0Structural)) {
        Add-UniqueItem -List $p1 -Text "Add one clear conversion path after core structural routes are strong enough."
    }
    else {
        Add-UniqueItem -List $p2 -Text "Monetization path is still missing, but it is not the first repair priority."
    }

    if ($p0.Count -eq 0 -and $p1.Count -eq 0 -and $p2.Count -eq 0) {
        Add-UniqueItem -List $p1 -Text "No critical blockers detected, but route quality can be improved."
    }

    # -------------------------
    # DO NEXT LIMIT = 3
    # -------------------------
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

    # -------------------------
    # TARGET STATE
    # -------------------------
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

    # -------------------------
    # OUTPUT
    # -------------------------
    $result = [ordered]@{
        site_stage          = $siteStage
        core_problem        = $coreProblem
        p0                  = (Join-OrNull -List $p0)
        p1                  = (Join-OrNull -List $p1)
        p2                  = (Join-OrNull -List $p2)
        missing             = (Join-OrNull -List $missing)
        do_next             = (Join-OrNull -List $doNextTrim)
        target_state_30_days= $targetState30
    }

    return [pscustomobject]$result
}
