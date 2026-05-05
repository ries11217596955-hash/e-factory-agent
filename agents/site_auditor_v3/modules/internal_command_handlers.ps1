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

    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add("/")

    if ($PipelineState.input.primary_route) {
        [void]$candidates.Add([string]$PipelineState.input.primary_route)
    }

    if ($PipelineState.route_audit -and $PipelineState.route_audit.routes) {
        foreach ($r in @($PipelineState.route_audit.routes)) {
            if ($r.path) { [void]$candidates.Add([string]$r.path) }
        }
    }

    try {
        $root = Invoke-WebRequest -Uri ($base + "/") -UseBasicParsing -TimeoutSec 10
        $html = [string]$root.Content
        $matches = [regex]::Matches($html, 'href=["'']([^"'']+)["'']')

        foreach ($m in $matches) {
            $href = [string]$m.Groups[1].Value
            $path = Normalize-InternalRoutePath -Href $href -BaseUri $baseUri
            if (-not $path) { continue }

            $depth = Get-RouteDepth -Path $path
            if ($depth -le $maxDepth) {
                [void]$candidates.Add($path)
            }

            if ($candidates.Count -ge $maxRoutes) { break }
        }
    }
    catch {
        # root fetch failure is captured through route checks below
    }

    $paths = @($candidates | Where-Object { $_ } | ForEach-Object {
        $p = [string]$_
        if ($p -eq "") { "/" }
        elseif ($p.StartsWith("/")) { $p }
        else { "/" + $p }
    } | Select-Object -Unique | Select-Object -First $maxRoutes)

    $discovered = @()
    $rejected = @()

    foreach ($p in $paths) {
        $url = $base + $p
        $check = Test-RouteUrl -Url $url
        if ($check.ok) {
            $discovered += @{
                path = $p
                url = $url
                status = "OK"
            }
        } else {
            $rejected += @{
                path = $p
                url = $url
                status = "REJECTED"
                reason = $check.error
            }
        }
    }

    return @{
        status = "OK"
        data = @{
            capability_id = "route_discovery"
            mode = "READ_ONLY"
            source = "base_url_plus_existing_candidates_plus_root_links"
            scan_profile = $scanProfile
            discovery_limit = $maxRoutes
            max_depth = $maxDepth
            hard_cap_routes = $hardCap
            truncated = ($candidates.Count -gt $paths.Count)
            checked_count = $paths.Count
            discovered_count = $discovered.Count
            rejected_count = $rejected.Count
            discovered_routes = $discovered
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
