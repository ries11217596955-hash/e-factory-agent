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
                "03_selection" { "Select audit targets"; break }
                "04_capture" { "Capture structured route evidence"; break }
                "08_visual_capture" { "Capture visual/html signals"; break }
                "05_reconcile" { "Reconcile evidence into findings/actions"; break }
                "06_decision" { "Evaluate verdict, score, limitations, diagnostic state"; break }
                "08_execution" { "Translate decision action into safe execution plan/result"; break }
                "08_route_feedback" { "Normalize execution route discovery into route feedback state"; break }
                "08_route_promotion" { "Promote route feedback into promoted audit/selection state"; break }
                "09_capability_builder" { "Produce build state and build recommendation only"; break }
                "10_post_build_decision" { "Apply build truth gate and final decision action override"; break }
                "07_output" { "Compose and write operator artifacts"; break }
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

    return [ordered]@{
        schema_version = "1.0.0"
        artifact = "AGENT_MAP"
        run_id = if ($PipelineState.run -and $PipelineState.run.run_id) { $PipelineState.run.run_id } else { "unknown" }
        product_scope = "Universal audit engine; website LINK is current execution lane only"
        agent_loop = "input -> audit -> evidence -> decision -> action -> next loop"
        registry_source = $registryPath
        entrypoint = $registry.entrypoint_path
        module_count = @($modules).Count
        modules = $modules
        current_bottleneck = $currentBottleneck
        protected_architecture_rules = @(
            "06_decision does not own action mapping",
            "07_output does not own next_step shape",
            "09_capability_builder does not emit decision_action",
            "build_truth_gate required when build_status exists",
            "module registry is SSOT for module order and state reads/writes",
            "build capability packs, not one-off isolated checks or one module per finding type"
        )
        runpack_links = [ordered]@{
            run_report = "RUN_REPORT.json"
            task = "TASK.json"
            agent_map_json = "AGENT_MAP.json"
            agent_map_md = "AGENT_MAP.md"
            artifact_manifest = "ARTIFACT_MANIFEST.json"
        }
        operator_reminder = [ordered]@{
            rule = "Choose one bottleneck. Patch only owner module. Build capability packs, not one-off checks. Verify with wrapper and guards."
            forbidden = @(
                "blind refactor",
                "feature before structural guard",
                "claim DONE without runtime proof",
                "manual module map edits",
                "new module for every isolated finding type",
                "one-parameter-at-a-time auditor construction when a capability pack is required"
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
    $lines.Add("## Current bottleneck")
    $lines.Add("- owner_module: $($AgentMap.current_bottleneck.owner_module)")
    $lines.Add("- action_id: $($AgentMap.current_bottleneck.action_id)")
    $lines.Add("- reason: $($AgentMap.current_bottleneck.reason)")
    $lines.Add("- next_action: $($AgentMap.current_bottleneck.next_action)")
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
