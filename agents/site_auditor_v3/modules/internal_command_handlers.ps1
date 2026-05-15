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
    $scopeStatus = if ($truncated) {
        "PARTIAL"
    } elseif ($sitemapFetched) {
        "COMPLETE"
    } else {
        "PARTIAL"
    }
    $scopeReason = if ($truncated) {
        "route_discovery_limits_reached"
    } elseif ($sitemapFetched) {
        "sitemap_and_recursive_sources_exhausted_without_route_cap"
    } else {
        "recursive_discovery_without_sitemap_remains_depth_bounded"
    }

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
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter()]$TaskOverride
    )

    $selfBuild = if ($PipelineState.decision -and $PipelineState.decision.self_build) { $PipelineState.decision.self_build } else { $null }
    $completedCapabilities = if ($selfBuild -and $selfBuild.completed_capabilities) { @($selfBuild.completed_capabilities) } else { @() }
    $missingCapabilities = if ($selfBuild -and $selfBuild.missing_capabilities) { @($selfBuild.missing_capabilities) } else { @() }
    $weakCapabilities = if ($selfBuild -and $selfBuild.weak_capabilities) { @($selfBuild.weak_capabilities) } else { @() }

    $overrideCapability = if ($TaskOverride -and $TaskOverride.selected_capability) { [string]$TaskOverride.selected_capability } else { "" }
    $nextCapability = if (-not [string]::IsNullOrWhiteSpace($overrideCapability)) {
        $overrideCapability
    } elseif ($selfBuild -and $selfBuild.next_capability_to_build) {
        [string]$selfBuild.next_capability_to_build
    } else {
        "route_discovery"
    }

    $taskTypeOverride = if ($TaskOverride -and $TaskOverride.task_type) { [string]$TaskOverride.task_type } else { "" }
    $stateKeyOverride = if ($TaskOverride -and $TaskOverride.state_key) { [string]$TaskOverride.state_key } else { "" }
    $requiredFieldsOverride = if ($TaskOverride -and $TaskOverride.required_fields) { @($TaskOverride.required_fields) } else { @() }
    $diagnosticReasonOverride = if ($TaskOverride -and $TaskOverride.diagnostic_reason) { [string]$TaskOverride.diagnostic_reason } else { "" }
    $selectionReason = if ($TaskOverride -and $TaskOverride.selection_reason) { [string]$TaskOverride.selection_reason } else { $null }
    $whyUniversal = if ($TaskOverride -and $TaskOverride.why_universal) { [string]$TaskOverride.why_universal } else { $null }

    if ($nextCapability -eq "capability_discovery" -and [string]::IsNullOrWhiteSpace($overrideCapability)) {
        return @{
            status = "OK"
            data = @{
                result = @{
                    capability_id = "capability_discovery"
                    task_type = "DISCOVER_CAPABILITY"
                    input = @{
                        selected = "capability_discovery"
                        completed_capabilities = @($completedCapabilities)
                        missing_capabilities = @($missingCapabilities)
                        weak_capabilities = @($weakCapabilities)
                        source = "RUN_REPORT.agent_capability_state.next_capability_to_build"
                    }
                    expected_output = @{
                        state_key = "capability_discovery"
                        required_fields = @("candidate_capabilities","selected_capability","selection_reason")
                    }
                    diagnostic = @{
                        reason = "self-build queue exhausted; discover the next universal audit capability pack"
                    }
                }
            }
        }
    }

    $taskType = if (-not [string]::IsNullOrWhiteSpace($taskTypeOverride)) { $taskTypeOverride } else { "BUILD_CAPABILITY" }
    $stateKey = if (-not [string]::IsNullOrWhiteSpace($stateKeyOverride)) { $stateKeyOverride } else { $nextCapability }
    $requiredFields = if ($requiredFieldsOverride.Count -gt 0) {
        @($requiredFieldsOverride)
    } elseif ($nextCapability -eq "route_discovery") {
        @("discovered_routes","rejected_routes","checked_count","discovered_count")
    } else {
        @("capability_id","build_status","validation")
    }
    $diagnosticReason = if (-not [string]::IsNullOrWhiteSpace($diagnosticReasonOverride)) {
        $diagnosticReasonOverride
    } elseif (-not [string]::IsNullOrWhiteSpace($overrideCapability)) {
        "task capability derived from capability discovery selection"
    } else {
        "task capability derived from self-build truth"
    }

    return @{
        status = "OK"
        data = @{
            result = @{
                capability_id = $nextCapability
                task_type = $taskType
                input = @{
                    candidates = @($nextCapability)
                    selected = $nextCapability
                    evidence_gaps = if ($nextCapability -eq "route_discovery") { @("baseline_coverage_or_route_discovery_needed") } else { @("self_build_selected_capability") }
                    source = if (-not [string]::IsNullOrWhiteSpace($overrideCapability)) { "RUN_REPORT.capability_discovery.selected_capability" } else { "RUN_REPORT.agent_capability_state.next_capability_to_build" }
                    selection_reason = $selectionReason
                    why_universal = $whyUniversal
                }
                expected_output = @{
                    state_key = $stateKey
                    required_fields = @($requiredFields)
                }
                diagnostic = @{
                    reason = $diagnosticReason
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
        return Invoke-PrepareCapabilityTaskInternal -PipelineState $PipelineState -TaskOverride $Command.args
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
