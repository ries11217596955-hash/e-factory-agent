import json
import re
import sys
from pathlib import Path

ROOT = Path("agents/site_auditor_v3")
FAILS = []

def text(path):
    p = Path(path)
    if not p.exists():
        FAILS.append(f"missing file: {path}")
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

decision = text(ROOT / "modules/06_decision.ps1")
action_map = text(ROOT / "lib/decision_action_map.ps1")
next_step = text(ROOT / "lib/decision_next_step.ps1")
output = text(ROOT / "modules/07_output.ps1")
builder = text(ROOT / "modules/09_capability_builder.ps1")
registry_path = ROOT / "contracts/module_registry.json"

# 1) 06_decision must not own action mapping objects.
for forbidden in [
    'action_id = "expand_routes"',
    'action_id = "improve_capture"',
    'action_id = "fix_findings"',
    'action_id = "prepare_next_capability_task"',
    'action_id = "integrate_generated_capability"',
]:
    if forbidden in decision:
        FAILS.append(f"06_decision owns action mapping: {forbidden}")

if "New-SiteAuditorV3DecisionAction" not in decision:
    FAILS.append("06_decision does not call decision_action_map helper")

# 2) decision_action_map must own action selection.
for required in [
    "function New-SiteAuditorV3DecisionAction",
    'action_id = "expand_routes"',
    'action_id = "fix_findings"',
]:
    if required not in action_map:
        FAILS.append(f"decision_action_map missing: {required}")

# 3) 07_output must not directly build next_step shape.
if "instruction =" in output and "New-SiteAuditorV3DecisionNextStepBlock" not in output:
    FAILS.append("07_output appears to build next_step directly")

if "New-SiteAuditorV3DecisionNextStepBlock" not in output:
    FAILS.append("07_output does not use decision_next_step helper")

# 4) next_step contract shape required.
for required in ["action_id", "action", "instruction", "target_module", "why"]:
    if re.search(rf"\b{required}\s*=", next_step) is None:
        FAILS.append(f"decision_next_step missing contract field: {required}")

# 5) builder must not emit decision_action.
if re.search(r"\bdecision_action\b", builder):
    FAILS.append("09_capability_builder must not emit decision_action")

# 6) module registry contract basics.
if not registry_path.exists():
    FAILS.append("module_registry.json missing")
else:
    reg = json.loads(registry_path.read_text(encoding="utf-8"))
    modules = reg.get("modules", [])
    if not modules:
        FAILS.append("module_registry has no modules")
    for m in modules:
        mid = m.get("module_id", "UNKNOWN")
        for key in ["module_id", "file_path", "entry_function", "reads_state_paths", "writes_state_paths"]:
            if key not in m:
                FAILS.append(f"registry module {mid} missing {key}")
        fp = m.get("file_path")
        if fp and not Path(fp).exists():
            FAILS.append(f"registry module {mid} file_path missing physically: {fp}")

# 7) Runtime AGENT_MAP contract when RUN_REPORT_PATH is provided.
import os

run_report_path = os.environ.get("RUN_REPORT_PATH")
if run_report_path:
    rp = Path(run_report_path)
    if not rp.exists():
        FAILS.append(f"RUN_REPORT_PATH missing physically: {run_report_path}")
    else:
        run_report = json.loads(rp.read_text(encoding="utf-8-sig"))
        run_dir = rp.parent

        agent_map_ref = run_report.get("agent_map")
        if not isinstance(agent_map_ref, dict):
            FAILS.append("RUN_REPORT missing agent_map reference")
        else:
            for key in ["json", "markdown"]:
                if key not in agent_map_ref:
                    FAILS.append(f"RUN_REPORT agent_map missing {key}")

        agent_map_json = run_dir / "AGENT_MAP.json"
        agent_map_md = run_dir / "AGENT_MAP.md"

        if not agent_map_json.exists():
            FAILS.append("AGENT_MAP.json missing in run directory")
        if not agent_map_md.exists():
            FAILS.append("AGENT_MAP.md missing in run directory")

        if agent_map_json.exists():
            agent_map = json.loads(agent_map_json.read_text(encoding="utf-8-sig"))
            modules = agent_map.get("modules", [])
            registry_ids = [m.get("module_id") for m in json.loads(registry_path.read_text(encoding="utf-8")).get("modules", [])]
            map_ids = [m.get("module_id") for m in modules]

            if agent_map.get("module_count") != len(registry_ids):
                FAILS.append("AGENT_MAP module_count does not match registry")
            if map_ids != registry_ids:
                FAILS.append("AGENT_MAP module order/id list does not match registry")

            for m in modules:
                mid = m.get("module_id", "UNKNOWN")
                for key in ["owner_responsibility", "reads_state_paths", "writes_state_paths", "runtime_status", "downstream_consumers"]:
                    if key not in m:
                        FAILS.append(f"AGENT_MAP module {mid} missing {key}")
                if m.get("owner_responsibility") in [None, "", "Module responsibility must be declared"]:
                    FAILS.append(f"AGENT_MAP module {mid} has undeclared owner_responsibility")

            bottleneck = agent_map.get("current_bottleneck")
            if not isinstance(bottleneck, dict):
                FAILS.append("AGENT_MAP missing current_bottleneck")
            else:
                for key in ["owner_module", "action_id", "reason", "next_action"]:
                    if not bottleneck.get(key):
                        FAILS.append(f"AGENT_MAP current_bottleneck missing {key}")


if FAILS:
    print("FAIL: V3 architecture guard")
    for f in FAILS:
        print("-", f)
    sys.exit(1)

print("PASS: V3 architecture guard")
