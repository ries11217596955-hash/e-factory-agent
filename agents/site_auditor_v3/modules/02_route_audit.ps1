function Invoke-RouteAuditModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $inputState = $InputData.input

    if ($inputState.status -eq "FAIL") {
        return @{
            status = "FAIL"
            data = @{ routes = @() }
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
        $routes += @{
            route_id = ("R{0:D3}" -f $i)
            path = [string]$path
            url = ($baseUrl + [string]$path)
            eligible = $true
        }
        $i++
    }

    return @{
        status = "OK"
        data = @{
            routes = $routes
            totals = @{
                discovered = $routes.Count
                eligible = $routes.Count
                excluded = 0
            }
        }
    }
}
