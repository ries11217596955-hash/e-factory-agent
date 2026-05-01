function Invoke-SelectionModule {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $routeAudit = $InputData.route_audit
    $routes = @($routeAudit.routes)

    return @{
        status = "OK"
        data = @{
            selected = $routes
            rejected = @()
            totals = @{
                selected = $routes.Count
                rejected = 0
            }
        }
    }
}
