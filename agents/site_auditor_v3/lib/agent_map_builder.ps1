function New-SiteAuditorV3AgentMap {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)][string]$RunRoot
    )

    $registryPath = "agents/site_auditor_v3/contracts/module_registry.json"
    $registry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json

    $modules = @()
    foreach ($m in @($registry.modules | Sort-Object ordinal)) {
        $writes = @($m.writes_state_paths)
        $runtimeStatus = "NOT_RUN"
        $lastOutputStatus = $null

        foreach ($w in $writes) {
            if ($PipelineState.ContainsKey($w)) {
                $runtimeStatus = "OK"
                $stateValue = $PipelineState[$w]
                if ($stateValue -and $stateValue.status) {
                    $lastOutputStatus = [string]$stateValue.status
                }
                break
            }
        }

        $modules += [ordered]@{
            module_id = $m.module_id
            ordinal = $m.ordinal
            enabled = $m.enabled
            file_path = $m.file_path
            entry_function = $m.entry_function
            owner_responsibility = switch -Regex ($m.module_id) {
                "01_input" { "Normalize request into input state"; break }
                "02_route_audit" { "Discover and qualify routes"; break }
                "03_selection" { "Select audit targets and own the session ledger entrypoint"; break }
                "03_5_route_bootstrap" { "Run pre-audit route scope discovery bootstrap"; break }
                "03_7_audit_selection" { "Finalize canonical audit selection from baseline or promoted routes"; break }
                "04_capture" { "Capture structured route evidence"; break }
                "08_visual_capture" { "Capture visual/html signals"; break }
                "05_reconcile" { "Reconcile evidence into findings/actions"; break }
                "06_decision" { "Evaluate verdict, score, limitations, diagnostic state"; break }
                "08_execution" { "Translate decision action into safe execution plan/result"; break }
                "08_route_feedback" { "Normalize execution route discovery into route feedback state"; break }
                "08_route_promotion" { "Promote route feedback into promoted audit/selection state"; break }
                "09_capability_builder" { "Produce build state and build recommendation only"; break }
                "09_5_capability_discovery" { "Resolve an exhausted self-build queue into the next universal capability pack"; break }
                "10_post_build_decision" { "Apply build/discovery truth gates and final decision action override"; break }
                "07_output" { "Compose operator artifacts, cumulative session truth, self-build truth, and AGENT_MAP"; break }
                default { "Module responsibility must be declared" }
            }
            reads_state_paths = @($m.reads_state_paths)
            writes_state_paths = @($m.writes_state_paths)
            depends_on = @($m.depends_on)
            runtime_status = $runtimeStatus
            last_output_status = $lastOutputStatus
            downstream_consumers = @($registry.modules | Where-Object {
                $reads = @($_.reads_state_paths)
                $hit = $false
                foreach ($w in $writes) {
                    if ($reads -contains $w) { $hit = $true }
                }
                $hit
            } | ForEach-Object { $_.module_id })
            failure_signal = if ($runtimeStatus -eq "OK") { $null } else { "state not written in this run" }
        }
    }

    $decisionAction = if ($PipelineState.post_build_decision -and $PipelineState.post_build_decision.decision_action) {
        $PipelineState.post_build_decision.decision_action
    } elseif ($PipelineState.decision -and $PipelineState.decision.decision_action) {
        $PipelineState.decision.decision_action
    } else {
        $null
    }

    $currentBottleneck = [ordered]@{
        owner_module = if ($decisionAction -and $decisionAction.target_module) { $decisionAction.target_module } else { "unknown" }
        action_id = if ($decisionAction -and $decisionAction.action_id) { $decisionAction.action_id } else { "unknown" }
        reason = if ($decisionAction -and $decisionAction.why) { $decisionAction.why } else { "unknown" }
        next_action = if ($decisionAction -and $decisionAction.action) { $decisionAction.action } else { "inspect RUN_REPORT decision_action" }
    }

    $auditSession = if ($PipelineState.selection) { $PipelineState.selection } else { $null }
    $sessionMode = if ($auditSession -and $auditSession.audit_action) { [string]$auditSession.audit_action } else { "UNKNOWN" }
    $sessionId = if ($auditSession -and $auditSession.session_id) { [string]$auditSession.session_id } else { $null }
    $sessionPending = if ($auditSession -and $null -ne $auditSession.next_pending_count) { [int]$auditSession.next_pending_count } else { $null }
    $routeFeedback = if ($PipelineState.route_feedback) { $PipelineState.route_feedback } else { $null }
    $routeScopeStatus = if ($routeFeedback -and $routeFeedback.scope_status) { [string]$routeFeedback.scope_status } else { "UNKNOWN" }
    $routeDiscovered = if ($routeFeedback -and $null -ne $routeFeedback.pages_discovered_count) { [int]$routeFeedback.pages_discovered_count } else { $null }
    $capabilityDiscovery = if ($PipelineState.capability_discovery) { $PipelineState.capability_discovery } else { $null }

    $systemCapabilities = @(
        [ordered]@{
            capability_id = "operator_run_modes"
            status = "ACTIVE"
            owner = "workflow + session helpers"
            summary = "GitHub Actions operator menu supports START, NEXT, and FULL intents."
            evidence = @(
                ".github/workflows/site-auditor-v3.yml",
                "agents/site_auditor_v3/tools/workflow_session_state.py",
                "agents/site_auditor_v3/tools/workflow_full_loop.py"
            )
        },
        [ordered]@{
            capability_id = "session_resume_from_single_artifact"
            status = "ACTIVE"
            owner = "workflow_session_state.py"
            summary = "NEXT/FULL restore audit ledger state from the unified report artifact rather than asking the operator for session_id."
            evidence = @(
                "agents/site_auditor_v3/tools/workflow_session_state.py"
            )
        },
        [ordered]@{
            capability_id = "unified_report_artifact"
            status = "ACTIVE"
            owner = "workflow + output packaging"
            summary = "One artifact contains RUN_REPORT, AGENT_MAP, TASK, SESSION_STATE, and AUDIT_SESSION_LEDGER truth."
            evidence = @(
                ".github/workflows/site-auditor-v3.yml"
            )
        },
        [ordered]@{
            capability_id = "inventory_then_batch_250"
            status = "ACTIVE"
            owner = "input + route discovery + audit selection"
            summary = "Route inventory is discovered before auditing; the audit session then advances in batches capped at 250 pages."
            evidence = @(
                "agents/site_auditor_v3/modules/01_input.ps1",
                "agents/site_auditor_v3/modules/08_route_feedback.ps1",
                "agents/site_auditor_v3/modules/03_7_audit_selection.ps1"
            )
        },
        [ordered]@{
            capability_id = "session_inventory_truth_alignment"
            status = "ACTIVE"
            owner = "07_output"
            summary = "RUN_REPORT route_discovery_result reuses the same bootstrap discovery snapshot that feeds session inventory; output no longer re-crawls live routes and contradicts the ledger."
            evidence = @(
                "agents/site_auditor_v3/modules/07_output.ps1"
            )
        },
        [ordered]@{
            capability_id = "session_aggregation_and_finalization"
            status = "ACTIVE_PROVEN_HOSTED_FULL"
            owner = "session finalization engine + runtime/workflow entrypoints"
            summary = "Completed audit sessions are transformed into a stream-aware aggregate model, final operator report, final action plan, and findings index, with FINALIZED session-state publication. Hosted FULL workflow proof confirmed the contour end-to-end."
            evidence = @(
                "agents/site_auditor_v3/lib/session_finalization.ps1",
                "agents/site_auditor_v3/tools/finalize_session.ps1",
                "agents/site_auditor_v3/contracts/session_aggregation_contract.json",
                "agents/site_auditor_v3/tests/validate_session_finalization.py",
                "agents/site_auditor_v3/run.ps1",
                "agents/site_auditor_v3/tests/run_and_validate.sh",
                "agents/site_auditor_v3/tools/workflow_full_loop.py",
                "agents/site_auditor_v3/tools/workflow_session_state.py",
                "hosted FULL artifact: FINALIZATION_VALIDATION=PASS, SESSION_STATE_STATUS=FINALIZED, FULL_LOOP_STATUS=COMPLETED"
            )
        },
        [ordered]@{
            capability_id = "capability_discovery_engine"
            status = "IMPLEMENTED_PENDING_RUNTIME_PROOF"
            owner = "capability discovery catalog + runtime module + output/task truth alignment"
            summary = "When the fixed self-build queue is exhausted, the agent selects the next universal capability pack from a catalog and emits a concrete TASK for that pack instead of looping on an abstract capability_discovery placeholder."
            evidence = @(
                "agents/site_auditor_v3/contracts/capability_discovery_catalog.json",
                "agents/site_auditor_v3/modules/09_5_capability_discovery.ps1",
                "agents/site_auditor_v3/modules/internal_command_handlers.ps1",
                "agents/site_auditor_v3/modules/10_post_build_decision.ps1",
                "agents/site_auditor_v3/modules/07_output.ps1",
                "agents/site_auditor_v3/tests/validate_self_build_loop.py"
            )
        }
    )

    return [ordered]@{
        schema_version = "1.3.0"
        artifact = "AGENT_MAP"
        run_id = if ($PipelineState.run -and $PipelineState.run.run_id) { $PipelineState.run.run_id } else { "unknown" }
        product_scope = "Universal audit engine; website LINK is current execution lane only"
        agent_loop = "input -> inventory truth -> batch audit -> evidence -> decision -> session aggregation/finalization -> capability discovery -> next universal capability pack"
        registry_source = $registryPath
        entrypoint = $registry.entrypoint_path
        module_count = @($modules).Count
        modules = $modules
        system_capabilities = $systemCapabilities
        runtime_session_snapshot = [ordered]@{
            audit_action = $sessionMode
            session_id = $sessionId
            pending_after_selection = $sessionPending
            route_scope_status = $routeScopeStatus
            discovered_page_routes = $routeDiscovered
            finalization_owner = "tools/finalize_session.ps1"
            capability_discovery_status = if ($capabilityDiscovery -and $capabilityDiscovery.discovery_status) { [string]$capabilityDiscovery.discovery_status } else { "NOT_TRIGGERED" }
            selected_next_capability = if ($capabilityDiscovery -and $capabilityDiscovery.selected_capability) { [string]$capabilityDiscovery.selected_capability } else { $null }
        }
        current_bottleneck = $currentBottleneck
        protected_architecture_rules = @(
            "06_decision does not own action mapping",
            "07_output does not own next_step shape",
            "09_capability_builder does not emit decision_action",
            "09_5_capability_discovery resolves universal next capability only after self-build requests capability_discovery",
            "build_truth_gate required when build_status exists",
            "module registry is SSOT for module order and state reads/writes",
            "build capability packs, not one-off isolated checks or one module per finding type",
            "operator session continuity must be visible in report artifacts and AGENT_MAP",
            "output must reuse already-produced discovery truth, not re-crawl live routes during report composition",
            "session finalization must aggregate through report streams and disclose future unaggregated streams instead of collapsing into a one-off summary",
            "capability discovery must select a universal product capability, never a repair task for one test target"
        )
        runpack_links = [ordered]@{
            run_report = "RUN_REPORT.json"
            task = "TASK.json"
            agent_map_json = "AGENT_MAP.json"
            agent_map_md = "AGENT_MAP.md"
            artifact_manifest = "ARTIFACT_MANIFEST.json"
            session_state = "SESSION_STATE.json"
            latest_run_report = "LATEST_RUN_REPORT.json"
            ledger_root = "sessions/<session_id>/AUDIT_SESSION_LEDGER.json"
            session_aggregate = "SESSION_AGGREGATE.json"
            final_operator_report = "FINAL_OPERATOR_REPORT.md"
            final_action_plan = "FINAL_ACTION_PLAN.json"
            final_findings_index = "FINAL_FINDINGS_INDEX.json"
        }
        operator_reminder = [ordered]@{
            rule = "Choose one bottleneck. Patch only owner module. Build capability packs, not one-off checks. Verify with wrapper and guards."
            forbidden = @(
                "blind refactor",
                "feature before structural guard",
                "claim DONE without runtime proof",
                "manual module map edits",
                "new module for every isolated finding type",
                "one-parameter-at-a-time auditor construction when a capability pack is required",
                "single-report FINAL_SUMMARY shortcuts that bypass stream-aware session aggregation",
                "target-specific repair findings promoted into universal product roadmap"
            )
        }
    }
}

function Convert-SiteAuditorV3AgentMapToMarkdown {
    param([Parameter(Mandatory)]$AgentMap)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# AGENT_MAP")
    $lines.Add("")
    $lines.Add("## Product scope")
    $lines.Add([string]$AgentMap.product_scope)
    $lines.Add("")
    $lines.Add("## Agent loop")
    $lines.Add([string]$AgentMap.agent_loop)
    $lines.Add("")
    $lines.Add("## Runtime session snapshot")
    $lines.Add("- audit_action: $($AgentMap.runtime_session_snapshot.audit_action)")
    $lines.Add("- session_id: $($AgentMap.runtime_session_snapshot.session_id)")
    $lines.Add("- pending_after_selection: $($AgentMap.runtime_session_snapshot.pending_after_selection)")
    $lines.Add("- route_scope_status: $($AgentMap.runtime_session_snapshot.route_scope_status)")
    $lines.Add("- discovered_page_routes: $($AgentMap.runtime_session_snapshot.discovered_page_routes)")
    $lines.Add("- finalization_owner: $($AgentMap.runtime_session_snapshot.finalization_owner)")
    $lines.Add("- capability_discovery_status: $($AgentMap.runtime_session_snapshot.capability_discovery_status)")
    $lines.Add("- selected_next_capability: $($AgentMap.runtime_session_snapshot.selected_next_capability)")
    $lines.Add("")
    $lines.Add("## Current bottleneck")
    $lines.Add("- owner_module: $($AgentMap.current_bottleneck.owner_module)")
    $lines.Add("- action_id: $($AgentMap.current_bottleneck.action_id)")
    $lines.Add("- reason: $($AgentMap.current_bottleneck.reason)")
    $lines.Add("- next_action: $($AgentMap.current_bottleneck.next_action)")
    $lines.Add("")
    $lines.Add("## System capabilities")
    foreach ($c in @($AgentMap.system_capabilities)) {
        $lines.Add("")
        $lines.Add("### $($c.capability_id)")
        $lines.Add("- status: $($c.status)")
        $lines.Add("- owner: $($c.owner)")
        $lines.Add("- summary: $($c.summary)")
        $lines.Add("- evidence: $(@($c.evidence) -join ', ')")
    }
    $lines.Add("")
    $lines.Add("## Modules")
    foreach ($m in @($AgentMap.modules)) {
        $lines.Add("")
        $lines.Add("### $($m.ordinal) — $($m.module_id)")
        $lines.Add("- file: $($m.file_path)")
        $lines.Add("- entry: $($m.entry_function)")
        $lines.Add("- owner: $($m.owner_responsibility)")
        $lines.Add("- reads: $(@($m.reads_state_paths) -join ', ')")
        $lines.Add("- writes: $(@($m.writes_state_paths) -join ', ')")
        $lines.Add("- runtime_status: $($m.runtime_status)")
        $lines.Add("- downstream: $(@($m.downstream_consumers) -join ', ')")
    }
    $lines.Add("")
    $lines.Add("## Protected architecture rules")
    foreach ($r in @($AgentMap.protected_architecture_rules)) {
        $lines.Add("- $r")
    }
    $lines.Add("")
    $lines.Add("## Operator reminder")
    $lines.Add("- rule: $($AgentMap.operator_reminder.rule)")
    $lines.Add("- forbidden:")
    foreach ($f in @($AgentMap.operator_reminder.forbidden)) {
        $lines.Add("  - $f")
    }
    return ($lines -join [Environment]::NewLine)
}
