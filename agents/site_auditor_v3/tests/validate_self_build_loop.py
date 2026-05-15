import json, os, sys
from pathlib import Path

p = Path(os.environ.get("RUN_REPORT_PATH", ""))
if not p.exists():
    print("FAIL: RUN_REPORT_PATH missing")
    sys.exit(1)

j = json.loads(p.read_text(encoding="utf-8"))
errors = []

if not j.get("decision_action"):
    errors.append("decision_action missing")
if not j.get("execution"):
    errors.append("execution missing")
if not j.get("route_discovery_result"):
    errors.append("route_discovery_result missing")
if not j.get("task"):
    errors.append("task missing")

data = j.get("route_discovery_result") or {}
if data.get("capability_id") != "route_discovery":
    errors.append("route_discovery_result wrong capability")
if data.get("mode") != "READ_ONLY":
    errors.append("route_discovery_result not READ_ONLY")
if "discovered_routes" not in data:
    errors.append("discovered_routes missing")
if "rejected_routes" not in data:
    errors.append("rejected_routes missing")
if data.get("checked_count", 0) < 1:
    errors.append("checked_count < 1")
if not data.get("discovery_sources") or not isinstance(data.get("discovery_sources"), list):
    errors.append("discovery_sources missing/invalid")
if not data.get("scope_status"):
    errors.append("scope_status missing")
if "pages_discovered_count" not in data and "discovered_count" not in data:
    errors.append("page/discovered count missing")
if "rejected_routes" in data and not isinstance(data.get("rejected_routes"), list):
    errors.append("rejected_routes invalid shape")

self_build = j.get("agent_capability_state") or j.get("self_build") or {}
task = j.get("task") or {}
capability_discovery = j.get("capability_discovery") or {}
next_capability = self_build.get("next_capability_to_build")
task_capability = task.get("capability_id")

if not next_capability:
    errors.append("next_capability_to_build missing")
elif task_capability != next_capability:
    errors.append(
        f"TASK capability drift: task.capability_id={task_capability!r} "
        f"!= next_capability_to_build={next_capability!r}"
    )

if capability_discovery:
    if capability_discovery.get("discovery_status") != "SELECTED":
        errors.append("capability_discovery.discovery_status must be SELECTED")
    selected_capability = capability_discovery.get("selected_capability")
    if not selected_capability:
        errors.append("capability_discovery.selected_capability missing")
    elif selected_capability != next_capability:
        errors.append(
            f"capability discovery drift: selected_capability={selected_capability!r} "
            f"!= next_capability_to_build={next_capability!r}"
        )
    if not capability_discovery.get("selection_reason"):
        errors.append("capability_discovery.selection_reason missing")
    if not capability_discovery.get("candidate_capabilities"):
        errors.append("capability_discovery.candidate_capabilities missing")

if next_capability == "capability_discovery":
    if task.get("task_type") != "DISCOVER_CAPABILITY":
        errors.append("capability_discovery task_type must be DISCOVER_CAPABILITY")
    expected_output = task.get("expected_output") or {}
    if expected_output.get("state_key") != "capability_discovery":
        errors.append("capability_discovery expected_output.state_key mismatch")

if next_capability == "repair_execution_layer":
    if not capability_discovery:
        errors.append("repair_execution_layer requires capability_discovery block")
    if task.get("task_type") != "BUILD_CAPABILITY":
        errors.append("repair_execution_layer task_type must be BUILD_CAPABILITY")
    expected_output = task.get("expected_output") or {}
    if expected_output.get("state_key") != "repair_execution_layer":
        errors.append("repair_execution_layer expected_output.state_key mismatch")
    required_fields = expected_output.get("required_fields") or []
    for field in ("capability_id", "build_status", "plan_contract", "safety_gate", "validation"):
        if field not in required_fields:
            errors.append(f"repair_execution_layer required field missing: {field}")

if errors:
    print("FAIL: SELF_BUILD_LOOP_V1:", errors)
    sys.exit(1)

print("PASS: SELF_BUILD_LOOP_V1")
