function New-SiteAuditorV3DecisionAction {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)][string]$Verdict,
        [Parameter(Mandatory)]$Limitations,
        [Parameter(Mandatory)][bool]$HasFindings
    )

    $decisionAction = @{
        action_id = "unknown"
        priority = "normal"
        action = "none"
        why = "no_mapping"
        target_module = "none"
        next_command_hint = "none"
    }

    if ($Verdict -eq "INCONCLUSIVE" -and ($Limitations -contains "baseline_coverage_only")) {
        $decisionAction = @{
            action_id = "expand_routes"
            priority = "high"
            action = "run route_depth_expansion"
            why = "insufficient_route_coverage"
            target_module = "route_audit"
            next_command_hint = "build route_depth_expansion capability"
        }
    }
    elseif ($Verdict -eq "INCONCLUSIVE" -and ($Limitations -contains "low_coverage_confidence")) {
        $decisionAction = @{
            action_id = "improve_capture"
            priority = "high"
            action = "run capture_expansion"
            why = "low_coverage_confidence"
            target_module = "capture"
            next_command_hint = "build capture_expansion capability"
        }
    }
    elseif ($HasFindings) {
        $decisionAction = @{
            action_id = "fix_findings"
            priority = "medium"
            action = "analyze and resolve findings"
            why = "findings_present"
            target_module = "reconcile"
            next_command_hint = "build findings_action_mapping"
        }
    }
    elseif ($Verdict -eq "PASS") {
        $decisionAction = @{
            action_id = "prepare_next_capability_task"
            priority = "low"
            action = "advance to next capability layer"
            why = "clean_pass"
            target_module = "meta"
            next_command_hint = "build next selected capability"
        }
    }

    if ($PipelineState.build -and $PipelineState.build.build_status -eq "GENERATED") {
        $decisionAction = @{
            action_id = "integrate_generated_capability"
            action = "integrate generated capability"
            why = "build artifact exists but is not integrated"
            target_module = "capability_integration"
            priority = "highest"
        }
    }

    return $decisionAction
}
