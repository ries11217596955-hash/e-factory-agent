function Invoke-Module035RouteBootstrap {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    . "agents/site_auditor_v3/modules/internal_command_handlers.ps1"

    $command = @{ type = "internal"; handler = "route_discovery"; args = @{} }
    $result = Invoke-InternalCommand -Command $command -PipelineState $PipelineState

    if (-not $result -or $result.status -ne "OK") {
        return @{ status = "FAIL"; data = @{ source = "bootstrap.route_discovery"; available = $false; reason = "bootstrap_route_discovery_failed"; execution_result = $result } }
    }

    return @{
        status = "OK"
        data = @{
            source = "bootstrap.route_discovery"
            available = $true
            execution_result = $result
        }
    }
}
