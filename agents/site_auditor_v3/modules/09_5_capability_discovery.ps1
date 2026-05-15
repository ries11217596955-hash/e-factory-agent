function Invoke-Module095CapabilityDiscovery {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $decision = $PipelineState.decision
    $selfBuild = if ($decision -and $decision.self_build) { $decision.self_build } else { $null }
    $requestedCapability = if ($selfBuild -and $selfBuild.next_capability_to_build) { [string]$selfBuild.next_capability_to_build } else { "" }

    if ($requestedCapability -ne "capability_discovery") {
        return @{
            status = "OK"
            data = [ordered]@{
                discovery_status = "SKIPPED"
                reason = "self_build_next_capability_is_not_capability_discovery"
                requested_capability = $requestedCapability
                candidate_capabilities = @()
                selected_capability = $null
                selection_reason = $null
                selected_task_contract = $null
            }
        }
    }

    $catalogPath = "agents/site_auditor_v3/contracts/capability_discovery_catalog.json"
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        return @{
            status = "FAIL"
            data = [ordered]@{
                discovery_status = "FAILED"
                reason = "capability_discovery_catalog_missing"
                catalog_path = $catalogPath
            }
        }
    }

    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -AsHashtable
    $candidates = @($catalog.candidates)
    $ready = @($candidates | Where-Object {
        $_.status -eq "READY_TO_BUILD" -and $_.trigger_when_next_capability -eq "capability_discovery"
    } | Sort-Object @{ Expression = { -1 * [int]$_.priority }; Ascending = $true }, @{ Expression = { [string]$_.capability_id }; Ascending = $true })

    if ($ready.Count -eq 0) {
        return @{
            status = "FAIL"
            data = [ordered]@{
                discovery_status = "FAILED"
                reason = "no_ready_universal_capability_candidate"
                catalog_path = $catalogPath
                requested_capability = $requestedCapability
                candidate_capabilities = @($candidates)
                selected_capability = $null
                selection_reason = $null
                selected_task_contract = $null
            }
        }
    }

    $selected = $ready[0]
    $candidateSummaries = @($ready | ForEach-Object {
        [ordered]@{
            capability_id = [string]$_.capability_id
            capability_class = [string]$_.capability_class
            status = [string]$_.status
            priority = [int]$_.priority
            why_universal = [string]$_.why_universal
        }
    })

    return @{
        status = "OK"
        data = [ordered]@{
            discovery_status = "SELECTED"
            source = "capability_discovery_catalog"
            catalog_path = $catalogPath
            catalog_schema_version = [string]$catalog.schema_version
            requested_capability = $requestedCapability
            candidate_capabilities = @($candidateSummaries)
            selected_capability = [string]$selected.capability_id
            selected_capability_class = [string]$selected.capability_class
            selection_reason = [string]$selected.selection_reason
            why_universal = [string]$selected.why_universal
            required_repo_truth = @($selected.required_repo_truth)
            selected_task_contract = $selected.task_contract
        }
    }
}
