function Invoke-Module09CapabilityBuilder {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $handlerPath = "agents/site_auditor_v3/modules/internal_command_handlers.ps1"

    if (-not (Test-Path $handlerPath)) {
        return @{
            status = "FAIL"
            data = @{
                build_status = "FAILED"
                reason = "target handler file missing"
                target_file = $handlerPath
            }
        }
    }

    . (Resolve-Path $handlerPath).Path

    $taskResult = Invoke-InternalCommand -Command @{ type="internal"; handler="prepare_capability_task"; args=@{} } -PipelineState $PipelineState
    $task = if ($taskResult -and $taskResult.status -eq "OK") { $taskResult.data.result } else { $null }

    if (-not $task -or $task.task_type -ne "BUILD_CAPABILITY") {
        return @{
            status = "OK"
            data = @{
                build_status = "SKIPPED"
                reason = "no build task"
            }
        }
    }

    $capId = [string]$task.capability_id
    $functionName = "Invoke-GeneratedRouteDiscovery"

    if ($capId -eq "route_discovery" -and (Get-Command Invoke-RouteDiscoveryInternal -ErrorAction SilentlyContinue)) {
        return @{
            status = "OK"
            data = @{
                build_status = "ALREADY_AVAILABLE"
                capability_id = $capId
                mode = "EXISTING_HANDLER"
                target_file = $handlerPath
                existing_function = "Invoke-RouteDiscoveryInternal"
                reason = "route_discovery capability already exists in internal_command_handlers.ps1"
                validation = @{
                    target_file_exists = (Test-Path $handlerPath)
                    existing_function_found = $true
                }
                next_action = @{
                    action_id = "advance_after_existing_capability"
                    action = "advance after existing route discovery capability"
                    why = "route_discovery already has an executable internal handler"
                    source = "build_state"
                    priority = "high"
                    target_module = "capability_discovery"
                }
            }
        }
    }

    if ($capId -ne "route_discovery") {
        return @{
            status = "OK"
            data = @{
                build_status = "FAILED"
                reason = "unsupported capability"
                capability_id = $capId
            }
        }
    }

    $generatedCode = @'
function Invoke-GeneratedRouteDiscovery {
    param(
        [Parameter(Mandatory)]$PipelineState
    )

    $baseUrl = [string]$PipelineState.input.base_url
    $routes = @()

    if ($PipelineState.route_audit -and $PipelineState.route_audit.routes) {
        foreach ($r in @($PipelineState.route_audit.routes)) {
            if ($r.path -and $r.url) {
                $routes += @{
                    path = [string]$r.path
                    url = [string]$r.url
                    status = "OK"
                }
            }
        }
    }

    return @{
        status = "OK"
        data = @{
            capability_id = "route_discovery"
            mode = "GENERATED_READ_ONLY"
            generated_by = "09_capability_builder"
            discovered_routes = $routes
            discovered_count = @($routes).Count
            rejected_routes = @()
            rejected_count = 0
            checked_count = @($routes).Count
        }
    }
}
'@

    return @{
        status = "OK"
        data = @{
            build_status = "GENERATED"
            capability_id = $capId
            mode = "DRY_BUILD"
            target_file = $handlerPath
            generated_code = $generatedCode
            generated_function = $functionName
            validation = @{
                has_generated_code = (-not [string]::IsNullOrWhiteSpace($generatedCode))
                has_target_file = (-not [string]::IsNullOrWhiteSpace($handlerPath))
                target_file_exists = (Test-Path $handlerPath)
            }
            next_action = @{
                action_id = "integrate_generated_capability"
                action = "integrate generated capability"
                why = "builder produced generated_code and target_file"
                source = "build_state"
                priority = "highest"
                target_module = "capability_integration"
            }
        }
    }
}
