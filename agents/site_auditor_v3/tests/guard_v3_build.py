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
    "identity",
    "operator_instruction",
    "agent_capability_state",
    "decision_action",
    "next_step",
    "forbidden_steps",
]

missing = [k for k in required if k not in j]
if missing:
    print("FAIL: guard missing keys:", missing)
    sys.exit(1)

decision_action = str(j.get("decision_action", {}).get("action", "")).lower()
next_action = str(j.get("next_step", {}).get("action", "")).lower()

if not decision_action or next_action != decision_action:
    print("FAIL: next_step not tied to decision_action")
    sys.exit(1)

forbidden = j.get("forbidden_steps", [])
if not isinstance(forbidden, list) or not forbidden:
    print("FAIL: forbidden_steps missing or empty")
    sys.exit(1)

build = j.get("build") or {}
if isinstance(build, dict):
    if "decision_action" in build:
        print("FAIL: build emitted decision_action")
        sys.exit(1)

    if build.get("next_action") and not build.get("build_recommendation"):
        print("FAIL: build action missing build_recommendation")
        sys.exit(1)

    if build.get("next_action") and build.get("build_recommendation") != build.get("next_action"):
        print("FAIL: next_action is not a compatibility alias")
        sys.exit(1)

    gate = j.get("build_truth_gate") or {}
    if build.get("build_status") and not gate:
        print("FAIL: build_truth_gate missing")
        sys.exit(1)

    if gate and (gate.get("checked") is not True or not str(gate.get("reason", "")).strip()):
        print("FAIL: build_truth_gate incomplete")
        sys.exit(1)

    if build.get("build_status") == "ALREADY_AVAILABLE":
        if gate.get("passed") is not True:
            print("FAIL: ALREADY_AVAILABLE build_truth_gate failed")
            sys.exit(1)
        if gate.get("mode") != "EXISTING_HANDLER":
            print("FAIL: ALREADY_AVAILABLE build_truth_gate mode mismatch")
            sys.exit(1)
        if gate.get("command_available") is not True and gate.get("function_in_target") is not True:
            print("FAIL: ALREADY_AVAILABLE existing_function not verified")
            sys.exit(1)

print("V3_BUILD_GUARD_PASS")
