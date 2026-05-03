import json
import sys
import os
from pathlib import Path

errors = []

def fail(code, msg):
    errors.append(f"{code}: {msg}")

# === GET REPORT PATH ===
report_path = Path(os.environ.get("RUN_REPORT_PATH", ""))

if not report_path or not report_path.exists():
    fail("RUN_REPORT_MISSING", str(report_path))

else:
    try:
        j = json.loads(report_path.read_text(encoding="utf-8"))
    except Exception as e:
        fail("RUN_REPORT_READ_FAIL", str(e))
        j = {}

    # === BASIC STRUCTURE CHECK ===
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

    for k in required_top:
        if k not in j:
            fail("RUN_REPORT_MISSING_KEY", k)

    # === DIAGNOSTIC CHECK ===
    d = j.get("diagnostic_summary", {})
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

    for k in diag_required:
        if k not in d:
            fail("RUN_REPORT_DIAGNOSTIC_MISSING_KEY", k)

    # === NEXT STEP LINK CHECK ===
    cap = str(j.get("agent_capability_state", {}).get("next_capability_to_build", "")).lower()
    action = str(j.get("next_step", {}).get("action", "")).lower()

    if cap and cap not in action:
        fail("RUN_REPORT_NEXT_STEP_NOT_TIED_TO_CAPABILITY", f"cap={cap}; action={action}")

# === RESULT ===
if errors:
    print("V3_BUILD_GUARD_FAIL")
    for e in errors:
        print("-", e)
    sys.exit(1)

print("V3_BUILD_GUARD_PASS")
