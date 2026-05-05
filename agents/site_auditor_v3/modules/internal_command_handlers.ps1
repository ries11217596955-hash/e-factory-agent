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

function Invoke-RouteDiscoveryInternal {
    param([Parameter(Mandatory)]$PipelineState)

    $baseUrl = [string]$PipelineState.input.base_url
    $base = $baseUrl.TrimEnd("/")
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
            if ($href.StartsWith("/")) {
                [void]$candidates.Add($href.Split("#")[0].Split("?")[0])
            }
            elseif ($href.StartsWith($base)) {
                $u = [System.Uri]$href
                [void]$candidates.Add($u.AbsolutePath)
            }
        }
    }
    catch {
        # root fetch failure is captured through route checks below
    }

    $paths = @($candidates | Where-Object { $_ } | ForEach-Object {
        if ($_ -eq "") { "/" }
        elseif ($_.StartsWith("/")) { $_ }
        else { "/" + $_ }
    } | Select-Object -Unique)

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
