function Invoke-Module10PostBuildDecision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $baseDecision = $PipelineState.decision
    $build = $PipelineState.build
    $buildRecommendation = if ($build -and $build.build_recommendation) {
        $build.build_recommendation
    } elseif ($build -and $build.next_action) {
        $build.next_action
    } else {
        $null
    }

    if ($build -and $build.build_status -eq "GENERATED" -and $buildRecommendation) {
        $targetFile = if ($build.target_file) { [string]$build.target_file } else { "" }
        $generatedFunction = if ($build.generated_function) { [string]$build.generated_function } else { "" }
        $targetExists = (-not [string]::IsNullOrWhiteSpace($targetFile)) -and (Test-Path -LiteralPath $targetFile)
        $functionIntegrated = $false
        $truthReason = ""

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
                    build_truth_gate = @{
                        checked = $true
                        passed = $false
                        target_file = $targetFile
                        generated_function = $generatedFunction
                        reason = $truthReason
                    }
                }
            }
        }

        return @{
            status = "OK"
            data = @{
                decision_action = $buildRecommendation
                source = "post_build_decision"
                reason = "build generated recommendation"
                build_truth_gate = @{
                    checked = $true
                    passed = $true
                    target_file = $targetFile
                    generated_function = $generatedFunction
                    reason = "generated function found in target_file"
                }
            }
        }
    }

    return @{
        status = "OK"
        data = @{
            decision_action = $baseDecision.decision_action
            source = "base_decision"
            reason = "no build override"
        }
    }
}
