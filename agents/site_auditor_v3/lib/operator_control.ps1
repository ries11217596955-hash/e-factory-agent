function New-SiteAuditorV3OperatorControlBlock {
    return [ordered]@{
        role = [ordered]@{
            who_i_am = "System Operator / Product Lead"
            what_i_build = @(
                "Universal Site Auditor self-build agent",
                "agent orchestration system",
                "Automation KB website as decision/action/monetization system"
            )
            business_goal = "Traffic -> Decision -> Action -> Monetization"
            agent_goal = "input -> audit -> evidence -> decision -> action -> next loop"
        }

        working_law = [ordered]@{
            sequence = "DIAGNOSE -> RUN -> VERIFY -> DECIDE -> PATCH"
            never = @(
                "do not guess",
                "do not patch before diagnosis",
                "do not trust PASS without validator",
                "do not trust GENERATED without generated_code and target_file",
                "do not trust agent next_step before checking evidence"
            )
        }

        agent_architecture = [ordered]@{
            orchestration = "run.ps1 executes module_registry.json in ordinal order"
            modules_connected = @(
                "01_input",
                "02_route_audit",
                "03_selection",
                "04_capture",
                "08_visual_capture",
                "05_reconcile",
                "06_decision",
                "08_execution",
                "09_capability_builder",
                "10_post_build_decision",
                "07_output"
            )
            not_yet_connected = @(
                "capability_integration"
            )
        }

        before_new_agent_function = @(
            "read RUN_REPORT.json first",
            "verify latest run status and validator output",
            "inspect registry order and module owners",
            "check whether agent statement is supported by physical artifact",
            "identify one bottleneck",
            "patch only owner module",
            "run suite",
            "commit only after PASS"
        )

        agent_truth_check = [ordered]@{
            question = "Is the agent telling the truth?"
            checks = @(
                "if build_status=GENERATED then generated_code and target_file must exist",
                "if next_step says integrate then build artifact must exist",
                "if execution says OK then execution_result.data must exist",
                "if PASS then validator output must prove it",
                "if RUN_REPORT says task exists then TASK.json must physically exist"
            )
        }

        function_done_gate = [ordered]@{
            rule = "Do not close any function/step until every required check is verified."
            required_checks = @(
                "happy_path_pass",
                "fail_path_pass",
                "run_report_has_decision_action_and_next_step",
                "next_step_names_exact_owner_module",
                "reported_evidence_matches_actual_target",
                "operator_control_current_warning_is_fresh",
                "validator_does_not_crash",
                "runpack_exists",
                "post_commit_status_clean"
            )
            fail_rule = "If any required check is missing, stale, or unverified, the step is NOT DONE."
        }

        current_warning = "Use function_done_gate before closing the step. A green run is not enough if fail-path, evidence handoff, next_step, operator_control freshness, validator stability, runpack, or post-commit status are not verified."
    }
}
