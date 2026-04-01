function Get-TargetModel {
    param([string]$TargetPath)

    if (!(Test-Path -LiteralPath $TargetPath)) {
        throw "TARGET_FILE_NOT_FOUND: $TargetPath"
    }

    $raw = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "TARGET_FILE_EMPTY: $TargetPath"
    }

    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        throw "TARGET_JSON_INVALID: $TargetPath"
    }
}

function Invoke-TargetStageAudit {
    param(
        $Inventory,
        $SemanticIssues,
        $LinkIssues,
        $RenderAudit,
        [object]$Target
    )

    $pages = @($Inventory | Where-Object { $_.is_publishable })
    $routeSet = @{}
    foreach ($p in $pages) { $routeSet[$p.route] = $true }

    $requiredRoutes = @($Target.required_routes)
    $missingRoutes = @()
    foreach ($route in $requiredRoutes) {
        if (-not $routeSet.ContainsKey($route)) {
            $missingRoutes += $route
        }
    }

    $clusterResults = @()
    foreach ($cluster in @($Target.required_clusters)) {
        $count = @($pages | Where-Object { $_.cluster_id -eq $cluster.id }).Count
        $hubPresent = $false
        foreach ($hub in @($cluster.hub_routes)) {
            if ($routeSet.ContainsKey($hub)) { $hubPresent = $true }
        }

        $clusterResults += [PSCustomObject]@{
            cluster_id = $cluster.id
            min_pages = [int]$cluster.min_pages
            actual_pages = $count
            hub_present = $hubPresent
            status = $(if ($count -ge [int]$cluster.min_pages -and $hubPresent) { 'OK' } else { 'INCOMPLETE' })
        }
    }

    $requiredCoverage = 0
    if (@($requiredRoutes).Count -gt 0) {
        $requiredCoverage = [math]::Round(((@($requiredRoutes).Count - @($missingRoutes).Count) / [double]@($requiredRoutes).Count) * 100, 2)
    }

    $criticalBlockers = @()
    foreach ($r in @($missingRoutes)) {
        $criticalBlockers += [PSCustomObject]@{
            type = 'REQUIRED_ROUTE_MISSING'
            route = $r
            severity = 'P0'
        }
    }

    foreach ($i in @($LinkIssues)) {
        $criticalBlockers += [PSCustomObject]@{
            type = 'BROKEN_INTERNAL_LINK'
            route = $i.source_route
            target = $i.target_route
            severity = 'P1'
        }
    }

    foreach ($rr in @($RenderAudit | Where-Object { $_.status -ne 'OK' })) {
        $criticalBlockers += [PSCustomObject]@{
            type = 'RENDER_FAIL'
            route = $rr.route
            severity = 'P1'
        }
    }

    $stage = 'Skeleton'
    if ($requiredCoverage -ge 50) { $stage = 'Structure' }
    if ($requiredCoverage -ge 80) { $stage = 'Coverage' }
    if ($requiredCoverage -ge 100 -and @($criticalBlockers).Count -eq 0) { $stage = 'Hardening' }

    return [PSCustomObject]@{
        TargetAlignment = [PSCustomObject]@{
            required_route_count = @($requiredRoutes).Count
            missing_required_routes = $missingRoutes
            required_route_coverage_percent = $requiredCoverage
            required_clusters = $clusterResults
            publishable_pages = @($pages).Count
        }
        StageAssessment = [PSCustomObject]@{
            build_stage = $stage
            critical_blocker_count = @($criticalBlockers).Count
            critical_blockers = $criticalBlockers
        }
    }
}
