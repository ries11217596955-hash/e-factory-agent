function Invoke-Module10PostBuildDecision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $baseDecision = $PipelineState.decision
    $build = $PipelineState.build
    $capabilityDiscovery = $PipelineState.capability_discovery
    $buildRecommendation = if ($build -and $build.build_recommendation) {
        $build.build_recommendation
    } elseif ($build -and $build.next_action) {
        $build.next_action
    } else {
        $null
    }

    $buildStatus = if ($build -and $build.build_status) { [string]$build.build_status } else { "SKIPPED" }
    $targetFile = if ($build -and $build.target_file) { [string]$build.target_file } else { "" }
    $targetExists = (-not [string]::IsNullOrWhiteSpace($targetFile)) -and (Test-Path -LiteralPath $targetFile)
    $buildTruthGate = [ordered]@{
        checked = $true
        passed = $true
        build_status = $buildStatus
        target_file = $targetFile
        reason = ""
    }

    if ($capabilityDiscovery -and $capabilityDiscovery.discovery_status -eq "SELECTED") {
        $selectedCapability = [string]$capabilityDiscovery.selected_capability
        $selectedClass = [string]$capabilityDiscovery.selected_capability_class
        $selectionReason = [string]$capabilityDiscovery.selection_reason

        if ($buildStatus -eq "SKIPPED") {
            $buildTruthGate.reason = "no build task"
        } else {
            $buildTruthGate.reason = "capability discovery selected next universal build pack"
        }
        $buildTruthGate.discovery_status = "SELECTED"
        $buildTruthGate.selected_capability = $selectedCapability

        return @{
            status = "OK"
            data = @{
                decision_action = @{
                    action_id = "build_selected_capability_pack"
                    action = "build selected universal capability pack"
                    why = $selectionReason
                    target_module = $selectedCapability
                    selected_capability = $selectedCapability
                    selected_capability_class = $selectedClass
                    source = "capability_discovery"
                    priority = "highest"
                    next_command_hint = ("use TASK.json to build {0}" -f $selectedCapability)
                }
                source = "capability_discovery"
                reason = "capability discovery resolved next universal build pack"
                build_truth_gate = $buildTruthGate
                capability_discovery = $capabilityDiscovery
            }
        }
    }

    if ($buildStatus -eq "GENERATED") {
        $generatedFunction = if ($build.generated_function) { [string]$build.generated_function } else { "" }
        $functionIntegrated = $false
        $truthReason = ""

        $buildTruthGate.generated_function = $generatedFunction
        if (-not $targetExists) {
            $truthReason = "target_file missing"
        } elseif ([string]::IsNullOrWhiteSpace($generatedFunction)) {
            $truthReason = "generated_function missing"
        } else {
            $targetText = Get-Content -LiteralPath $targetFile -Raw
            $functionIntegrated = $targetText.Contains($generatedFunction)
            if (-not $functionIntegrated) {
                $truthReason = "generated function not found in target_file"
            }
        }

        $buildTruthGate.passed = ($targetExists -and $functionIntegrated)
        $buildTruthGate.reason = if ($buildTruthGate.passed) { "generated function found in target_file" } else { $truthReason }

        if (-not ($targetExists -and $functionIntegrated)) {
            return @{
                status = "OK"
                data = @{
                    decision_action = @{
                        action_id = "repair_build_truth_gate"
                        action = "repair build truth gate before integration"
                        why = "builder produced generated_code, but generated function is not physically integrated"
                        target_module = "post_build_decision"
                        target_file = "agents/site_auditor_v3/modules/10_post_build_decision.ps1"
                        source = "post_build_truth_gate"
                        priority = "highest"
                    }
                    source = "post_build_truth_gate"
                    reason = $truthReason
                    build_truth_gate = $buildTruthGate
                }
            }
        }

        if ($buildRecommendation) {
            return @{
                status = "OK"
                data = @{
                    decision_action = $buildRecommendation
                    source = "post_build_decision"
                    reason = "build generated recommendation"
                    build_truth_gate = $buildTruthGate
                }
            }
        }
    } elseif ($buildStatus -eq "ALREADY_AVAILABLE") {
        $existingFunction = if ($build.existing_function) { [string]$build.existing_function } else { "" }
        $modeValid = ($build.mode -eq "EXISTING_HANDLER")
        $commandAvailable = (-not [string]::IsNullOrWhiteSpace($existingFunction)) -and [bool](Get-Command $existingFunction -ErrorAction SilentlyContinue)
        $functionInTarget = $false

        if ($targetExists -and -not [string]::IsNullOrWhiteSpace($existingFunction)) {
            $targetText = Get-Content -LiteralPath $targetFile -Raw
            $functionInTarget = $targetText.Contains($existingFunction)
        }

        $buildTruthGate.existing_function = $existingFunction
        $buildTruthGate.mode = if ($build.mode) { [string]$build.mode } else { "" }
        $buildTruthGate.command_available = $commandAvailable
        $buildTruthGate.function_in_target = $functionInTarget
        $buildTruthGate.passed = ($targetExists -and $modeValid -and ($commandAvailable -or $functionInTarget))

        if (-not $targetExists) {
            $buildTruthGate.reason = "target_file missing"
        } elseif (-not $modeValid) {
            $buildTruthGate.reason = "mode is not EXISTING_HANDLER"
        } elseif (-not ($commandAvailable -or $functionInTarget)) {
            $buildTruthGate.reason = "existing_function unavailable"
        } else {
            $buildTruthGate.reason = "existing handler verified"
        }
    } elseif ($buildStatus -eq "SKIPPED") {
        $buildTruthGate.reason = "no build task"
    } elseif ($buildStatus -eq "FAILED") {
        $buildTruthGate.passed = $false
        $buildTruthGate.reason = if ($build -and $build.reason) { [string]$build.reason } else { "build failed" }
    } else {
        $buildTruthGate.reason = "unrecognized build status"
    }

    return @{
        status = "OK"
        data = @{
            decision_action = $baseDecision.decision_action
            source = "base_decision"
            reason = "no build override"
            build_truth_gate = $buildTruthGate
        }
    }
}
