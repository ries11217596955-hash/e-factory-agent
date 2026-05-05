#!/usr/bin/env bash
set -euo pipefail

ROOT="agents/site_auditor_v3"
RUNS="$ROOT/runs"

echo "=== CLEAN RUNS ==="
rm -rf "$RUNS"/* 2>/dev/null || true

echo "=== RUN AGENT ==="
pwsh -NoProfile -File "$ROOT/run.ps1" \
  -RequestPath "${REQUEST_PATH:-$ROOT/tests/fixtures/smoke.request.json}"

echo "=== FIND LATEST RUN_REPORT ==="
LATEST_REPORT="$(ls -1dt "$RUNS"/* 2>/dev/null | head -n1)/RUN_REPORT.json"
if [ ! -f "$LATEST_REPORT" ]; then
  echo "FAIL: RUN_REPORT not created"
  exit 1
fi

echo "LATEST_REPORT=$LATEST_REPORT"

echo "=== VALIDATE RUN_REPORT CONTRACT ==="
RUN_REPORT_PATH="$LATEST_REPORT" python3 "$ROOT/tests/validate_run_report.py"

echo "=== VALIDATE BUILD GUARD ==="
RUN_REPORT_PATH="$LATEST_REPORT" python3 "$ROOT/tests/guard_v3_build.py"

echo "=== VALIDATE SELF BUILD LOOP ==="
RUN_REPORT_PATH="$LATEST_REPORT" python3 "$ROOT/tests/validate_self_build_loop.py"

echo "=== SHORT SUMMARY ==="
python3 - "$LATEST_REPORT" <<'PY'
import json, sys
p = sys.argv[1]
j = json.loads(open(p).read())
print("run_id:", j["run_id"])
print("verdict:", j["verdict"])
print("score:", j["audit_result"]["score"])
print("next_capability:", j["agent_capability_state"]["next_capability_to_build"])
print("limitations:", j["diagnostic_summary"]["limitations"])
PY

echo "=== OPERATOR BRIEF FROM RUN_REPORT ==="
python3 - "$LATEST_REPORT" <<'PY'
import json, sys
p = sys.argv[1]
j = json.loads(open(p).read())

def get(path, default=None):
    cur = j
    for key in path:
        if isinstance(cur, dict):
            cur = cur.get(key, default)
        elif isinstance(cur, list) and isinstance(key, int) and 0 <= key < len(cur):
            cur = cur[key]
        else:
            return default
        if cur is None:
            return default
    return cur

done_gate = get(["operator_control", "function_done_gate", "required_checks"], [])
next_step = get(["next_step"], {}) or {}
decision = get(["decision_action"], {}) or {}
route_first = get(["route_discovery_result", "discovered_routes", 0], {}) or {}

print("operator_instruction:", get(["operator_instruction", "for_chatgpt"], "MISSING"))
print("current_warning:", get(["operator_control", "current_warning"], "MISSING"))
print("function_done_gate_checks:", len(done_gate))
print("next_step.action_id:", next_step.get("action_id", "MISSING"))
print("next_step.why:", next_step.get("why", "MISSING"))
print("next_step.target_module:", next_step.get("target_module", "MISSING"))
print("decision_action.action_id:", decision.get("action_id", "MISSING"))
print("route_first.path:", route_first.get("path", "MISSING"))
print("route_discovery_count:", get(["route_discovery_result", "discovered_count"], "MISSING"))
print("evidence_routes_discovered:", get(["evidence_summary", "routes_discovered"], "MISSING"))
print("evidence_routes_selected:", get(["evidence_summary", "routes_selected"], "MISSING"))
print("visual_first_url:", get(["evidence_summary", "visual_capture", "visual_records", 0, "url"], "MISSING"))
PY

echo "=== PACKAGE RUNPACK ==="
DELIVER_ROOT="$ROOT/_deliver"
mkdir -p "$DELIVER_ROOT"

RUN_DIR="$(dirname "$LATEST_REPORT")"
RUN_ID="$(basename "$RUN_DIR")"
ZIP_PATH="$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.zip"

if command -v zip >/dev/null 2>&1; then
  (cd "$RUN_DIR" && zip -qr "$(cd ../../_deliver && pwd)/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.zip" .)
else
  tar -czf "$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz" -C "$RUN_DIR" .
  ZIP_PATH="$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz"
fi

echo "DELIVERABLE=$ZIP_PATH"
echo "PASS: END-TO-END"
