import json
import os
import sys
from pathlib import Path

def resolve_report_path():
    if len(sys.argv) >= 2:
        return Path(sys.argv[1])
    env_path = os.environ.get("LATEST_REPORT")
    if env_path:
        return Path(env_path)
    reports = sorted(Path("agents/site_auditor_v3/runs").glob("*/RUN_REPORT.json"))
    if reports:
        return reports[-1]
    return None

p = resolve_report_path()
if not p or not p.exists():
    print("FAIL: RUN_REPORT missing")
    sys.exit(1)

j = json.loads(p.read_text(encoding="utf-8"))

required = [
    "read_me_first",
    "identity",
    "mission",
    "operator_instruction",
    "read_order",
    "audit_result",
    "evidence_summary",
    "diagnostic_summary",
    "agent_capability_state",
    "decision_action",
    "next_step",
    "forbidden_steps",
]

missing = [k for k in required if k not in j]
if missing:
    print("FAIL: missing RUN_REPORT keys:", missing)
    sys.exit(1)

decision_action = str(j.get("decision_action", {}).get("action", "")).lower()
next_action = str(j.get("next_step", {}).get("action", "")).lower()

if not decision_action or next_action != decision_action:
    print("FAIL: next_step not tied to decision_action")
    print("decision_action:", decision_action)
    print("next_step.action:", next_action)
    sys.exit(1)

forbidden = j.get("forbidden_steps", [])
if not isinstance(forbidden, list) or not forbidden:
    print("FAIL: forbidden_steps missing or empty")
    sys.exit(1)

print("PASS: RUN_REPORT contract")
