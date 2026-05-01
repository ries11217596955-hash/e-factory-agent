import json
import sys
from pathlib import Path

p = Path("agents/site_auditor_v3/runs/manual-smoke/RUN_REPORT.json")
if not p.exists():
    print("FAIL: RUN_REPORT missing")
    sys.exit(1)

j = json.loads(p.read_text())

required_top = [
    "read_me_first",
    "identity",
    "mission",
    "operator_instruction",
    "read_order",
    "if_problem_then_read",
    "pipeline_status",
    "audit_result",
    "evidence_summary",
    "diagnostic_summary",
    "agent_capability_state",
    "next_step",
    "forbidden_steps",
]

missing = [k for k in required_top if k not in j]
if missing:
    print("FAIL: missing top-level keys:", missing)
    sys.exit(1)

diag_required = [
    "failed_stage",
    "what_worked",
    "what_failed",
    "limitations",
    "evidence_gaps",
    "confidence",
    "next_debug_step",
    "next_build_step",
    "forbidden_next_steps",
]

d = j["diagnostic_summary"]
diag_missing = [k for k in diag_required if k not in d]
if diag_missing:
    print("FAIL: diagnostic missing keys:", diag_missing)
    sys.exit(1)

cap = j["agent_capability_state"]["next_capability_to_build"].lower()
action = j["next_step"]["action"].lower()

if cap and cap not in action:
    print("FAIL: next_step not tied to capability")
    print("capability:", cap)
    print("action:", action)
    sys.exit(1)

print("PASS: RUN_REPORT contract")
