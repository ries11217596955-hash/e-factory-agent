function New-RouteObject {
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Path
    )

    $cleanPath = if ($Path.StartsWith("/")) { $Path } else { "/" + $Path }
    $url = $BaseUrl.TrimEnd("/") + $cleanPath

    return @{
        route_id = ("R{0:D3}" -f $Index)
        path = $cleanPath
        url = $url
        eligible = $true
    }
}

function Expand-Routes {
    param(
        [Parameter(Mandatory)][array]$BaseRoutes,
        [Parameter(Mandatory)][string]$BaseUrl
    )

    # STRICT MODE: no fake expansion
    $expanded = @()
    $i = 1

    foreach ($r in @($BaseRoutes)) {
        if ($r -and $r.path) {
            $expanded += New-RouteObject -Index $i -BaseUrl $BaseUrl -Path ([string]$r.path)
            $i++
        }
    }

    return $expanded
}

function Invoke-RouteAuditModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $inputState = $InputData.input

    if ($inputState.status -eq "FAIL") {
        return @{
            status = "FAIL"
            data = @{
                routes = @()
                routes_original = @()
                routes_expanded_count = 0
                totals = @{
                    discovered = 0
                    eligible = 0
                    excluded = 0
                }
            }
        }
    }

    $baseUrl = [string]$inputState.base_url
    $allow = @($inputState.route_allowlist)

    if ($allow.Count -eq 0) {
        $allow = @("/")
    }

    $routes = @()
    $i = 1
    foreach ($path in $allow) {
        $routes += New-RouteObject -Index $i -BaseUrl $baseUrl -Path ([string]$path)
        $i++
    }

    $routesExpanded = @(Expand-Routes -BaseRoutes $routes -BaseUrl $baseUrl)

    return @{
        status = "OK"
        data = @{
            routes = $routesExpanded
            routes_original = $routes
            routes_expanded_count = $routesExpanded.Count
            totals = @{
                discovered = $routesExpanded.Count
                eligible = $routesExpanded.Count
                excluded = 0
            }
        }
    }
}
