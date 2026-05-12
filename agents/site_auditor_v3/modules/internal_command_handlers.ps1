function Test-RouteUrl {
    param([string]$Url)

    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
        return @{
            ok = $true
            status_code = 200
            url = $Url
        }
    }
    catch {
        $msg = $_.Exception.Message
        return @{
            ok = $false
            status_code = $null
            url = $Url
            error = $msg
        }
    }
}

function Normalize-InternalRoutePath {
    param(
        [Parameter(Mandatory)][string]$Href,
        [Parameter(Mandatory)][System.Uri]$BaseUri
    )

    $cleanHref = $Href.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanHref)) { return $null }
    if ($cleanHref.StartsWith("#")) { return $null }
    if ($cleanHref.StartsWith("mailto:")) { return $null }
    if ($cleanHref.StartsWith("tel:")) { return $null }
    if ($cleanHref.StartsWith("javascript:")) { return $null }

    $cleanHref = $cleanHref.Split("#")[0].Split("?")[0].Trim()
    if ([string]::IsNullOrWhiteSpace($cleanHref)) { return $null }

    try {
        $u = if ($cleanHref.StartsWith("/")) {
            [System.Uri]::new($BaseUri, $cleanHref)
        } elseif ($cleanHref -match "^https?://") {
            [System.Uri]$cleanHref
        } else {
            [System.Uri]::new($BaseUri, $cleanHref)
        }

        if ($u.Host -ne $BaseUri.Host) { return $null }

        $path = $u.AbsolutePath
        if ([string]::IsNullOrWhiteSpace($path)) { return "/" }
        if (-not $path.StartsWith("/")) { $path = "/" + $path }
        if (($path.Length -gt 1) -and $path.EndsWith("/")) { $path = $path.TrimEnd("/") }
        return $path
    }
    catch {
        return $null
    }
}

function Get-RouteDepth {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -eq "/") { return 0 }
    return @($Path.Trim("/") -split "/" | Where-Object { $_ }).Count
}

function Test-AssetLikePath {
    param([string]$Path)
    if (-not $Path) { return $false }
    $p = [string]$Path
    if ($p -match '\.(css|js|webmanifest|png|jpg|jpeg|svg|ico|woff|woff2|gif|webp|bmp|tiff|map|pdf|zip|rar|7z|mp4|mp3|json|xml)$') { return $true }
    if ($p -match '^/(assets?|static|images?|img|fonts?|scripts?|js|css|media|downloads?)(/|$)') { return $true }
    if ($p -match '/(sitemap|feed)\.xml$') { return $true }
    return $false
}

function Invoke-RouteDiscoveryInternal {
    param([Parameter(Mandatory)]$PipelineState)

    $baseUrl = [string]$PipelineState.input.base_url
    $base = $baseUrl.TrimEnd("/")
    $baseUri = [System.Uri]$base

    $scanProfile = if ($PipelineState.input.scan_profile) { [string]$PipelineState.input.scan_profile } else { "STANDARD" }
    $maxRoutes = if ($PipelineState.input.max_routes) { [int]$PipelineState.input.max_routes } else { 50 }
    $maxDepth = if ($PipelineState.input.max_depth) { [int]$PipelineState.input.max_depth } else { 2 }
    $hardCap = if ($PipelineState.input.hard_cap_routes) { [int]$PipelineState.input.hard_cap_routes } else { 200 }
    if ($maxRoutes -gt $hardCap) { $maxRoutes = $hardCap }

    $pageCandidateQueue = New-Object System.Collections.ArrayList
    $allCandidates = New-Object System.Collections.ArrayList
    $discoverySources = New-Object System.Collections.ArrayList
    [void]$discoverySources.Add("baseline_candidates")
    $primaryRoute = if ($PipelineState.input.primary_route) { [string]$PipelineState.input.primary_route } else { "/" }

    if ($primaryRoute -and $primaryRoute -ne "/") {
        [void]$allCandidates.Add($primaryRoute)
        [void]$allCandidates.Add("/")
    } else {
        [void]$allCandidates.Add("/")
    }
    [void]$pageCandidateQueue.Add("/")

    if ($PipelineState.route_audit -and $PipelineState.route_audit.routes) {
        foreach ($r in @($PipelineState.route_audit.routes)) {
            if ($r.path) { [void]$allCandidates.Add([string]$r.path) }
        }
    }

    $sitemapFetched = $false
    $sitemapUri = $base + "/sitemap.xml"
    try {
        $sitemap = Invoke-WebRequest -Uri $sitemapUri -UseBasicParsing -TimeoutSec 10
        $sx = [string]$sitemap.Content
        foreach ($m in [regex]::Matches($sx, '<loc>\s*([^<]+)\s*</loc>')) {
            $path = Normalize-InternalRoutePath -Href ([string]$m.Groups[1].Value) -BaseUri $baseUri
            if ($path) {
                [void]$allCandidates.Add($path)
                [void]$pageCandidateQueue.Add($path)
                $sitemapFetched = $true
            }
        }
    } catch { }
    if ($sitemapFetched) { [void]$discoverySources.Add("sitemap_xml") }

    try {
        $root = Invoke-WebRequest -Uri ($base + "/") -UseBasicParsing -TimeoutSec 10
        $html = [string]$root.Content
        $matches = [regex]::Matches($html, 'href=["'']([^"'']+)["'']')
        $rootLinksAdded = $false

        foreach ($m in $matches) {
            $href = [string]$m.Groups[1].Value
            $path = Normalize-InternalRoutePath -Href $href -BaseUri $baseUri
            if (-not $path) { continue }

            $depth = Get-RouteDepth -Path $path
            if ($depth -le $maxDepth) {
                [void]$allCandidates.Add($path)
                [void]$pageCandidateQueue.Add($path)
                $rootLinksAdded = $true
            }

            if ($allCandidates.Count -ge $hardCap) { break }
        }
        if ($rootLinksAdded) { [void]$discoverySources.Add("root_links") }
    }
    catch {
        # root fetch failure is captured through route checks below
    }

    $discoveryLimit = [Math]::Min($maxRoutes, $hardCap)
    $normalizedPaths = @($allCandidates | Where-Object { $_ } | ForEach-Object {
        $p = [string]$_
        if ($p -eq "") { "/" }
        elseif ($p.StartsWith("/")) { $p }
        else { "/" + $p }
    } | Select-Object -Unique)

    $pageRoutes = @()
    $assetRoutes = @()
    $rejected = @()
    $visited = @{}
    $crawlQueue = New-Object System.Collections.Queue
    foreach ($path in @($pageCandidateQueue | Where-Object { $_ } | Select-Object -Unique)) {
        $crawlQueue.Enqueue(@{ path = $path; depth = (Get-RouteDepth -Path $path) })
    }
    [void]$discoverySources.Add("recursive_internal_crawl")

    while ($crawlQueue.Count -gt 0 -and ($pageRoutes.Count + $assetRoutes.Count) -lt $discoveryLimit) {
        $item = $crawlQueue.Dequeue()
        $p = [string]$item.path
        $depth = [int]$item.depth
        if ($visited.ContainsKey($p)) { continue }
        $visited[$p] = $true
        if ($depth -gt $maxDepth) { continue }

        if (Test-AssetLikePath -Path $p) {
            $assetRoutes += @{ path = $p; url = ($base + $p); status = "ASSET_EXCLUDED" }
            continue
        }
        $url = $base + $p
        $check = Test-RouteUrl -Url $url
        if ($check.ok) {
            $pageRoutes += @{
                path = $p
                url = $url
                status = "OK"
            }
            try {
                $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                if ($resp.Content) {
                    foreach ($m in [regex]::Matches([string]$resp.Content, 'href=["'']([^"'']+)["'']')) {
                        $child = Normalize-InternalRoutePath -Href ([string]$m.Groups[1].Value) -BaseUri $baseUri
                        if (-not $child) { continue }
                        $childDepth = Get-RouteDepth -Path $child
                        if ($childDepth -le $maxDepth -and -not $visited.ContainsKey($child)) {
                            $crawlQueue.Enqueue(@{ path = $child; depth = $childDepth })
                        }
                    }
                }
            } catch { }
        } else {
            $rejected += @{
                path = $p
                url = $url
                status = "REJECTED"
                reason = $check.error
            }
        }
    }

    foreach ($p in $normalizedPaths) {
        if (($pageRoutes | Where-Object { $_.path -eq $p }).Count -gt 0) { continue }
        if (($assetRoutes | Where-Object { $_.path -eq $p }).Count -gt 0) { continue }
        if (($rejected | Where-Object { $_.path -eq $p }).Count -gt 0) { continue }
        if (Test-AssetLikePath -Path $p) {
            $assetRoutes += @{ path = $p; url = ($base + $p); status = "ASSET_EXCLUDED" }
        }
    }
    $truncated = (($normalizedPaths.Count -gt $discoveryLimit) -or (($pageRoutes.Count + $assetRoutes.Count) -ge $discoveryLimit))
    $scopeStatus = if ($truncated -or $maxDepth -ge 0 -or $maxRoutes -lt $hardCap) { "PARTIAL" } else { "COMPLETE" }
    $scopeReason = if ($truncated) { "route_discovery_limits_reached" } else { "bounded_by_configured_depth_or_limits" }

    return @{
        status = "OK"
        data = @{
            capability_id = "route_discovery"
            mode = "READ_ONLY"
            source = "baseline_plus_root_plus_sitemap_plus_recursive_crawl"
            discovery_sources = @($discoverySources | Select-Object -Unique)
            scope_status = $scopeStatus
            scope_reason = $scopeReason
            scan_profile = $scanProfile
            discovery_limit = $discoveryLimit
            max_depth = $maxDepth
            hard_cap_routes = $hardCap
            truncated = $truncated
            checked_count = $visited.Keys.Count
            discovered_count = $pageRoutes.Count
            pages_discovered_count = $pageRoutes.Count
            assets_excluded_count = $assetRoutes.Count
            rejected_count = $rejected.Count
            page_routes = $pageRoutes
            asset_routes = $assetRoutes
            discovered_routes = $pageRoutes
            rejected_routes = $rejected
        }
    }
}

function Invoke-PrepareCapabilityTaskInternal {
    param([Parameter(Mandatory)]$PipelineState)

    return @{
        status = "OK"
        data = @{
            result = @{
                capability_id = "route_discovery"
                task_type = "BUILD_CAPABILITY"
                input = @{
                    candidates = @("route_discovery")
                    selected = "route_discovery"
                    evidence_gaps = @("baseline_coverage_or_route_discovery_needed")
                }
                expected_output = @{
                    state_key = "route_discovery"
                    required_fields = @("discovered_routes","rejected_routes","checked_count","discovered_count")
                }
                diagnostic = @{
                    reason = "execution-ready route discovery selected from coverage gap"
                }
            }
        }
    }
}

function Invoke-InternalCommand {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$PipelineState
    )

    if ($Command.handler -eq "prepare_capability_task") {
        return Invoke-PrepareCapabilityTaskInternal -PipelineState $PipelineState
    }

    if ($Command.handler -eq "route_discovery") {
        return Invoke-RouteDiscoveryInternal -PipelineState $PipelineState
    }

    return @{
        status = "UNKNOWN_COMMAND"
        data = @{
            handler = $Command.handler
        }
    }
}
