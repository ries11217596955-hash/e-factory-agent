#!/usr/bin/env bash
set -euo pipefail

ROOT="agents/site_auditor_v3"
RUNS="$ROOT/runs"
DEFAULT_TARGET_URL="https://automation-kb.pages.dev/"
DEFAULT_SCAN_PROFILE="STANDARD"
DEFAULT_REQUEST="$ROOT/tests/fixtures/smoke.request.json"
BUNDLED_PLACEHOLDER_FIXTURE="$ROOT/tests/fixtures/link.request.json"

REQUEST_INPUT="${REQUEST_PATH:-$DEFAULT_REQUEST}"
REQUEST_EFFECTIVE="$REQUEST_INPUT"
TMP_REQUEST=""

prepare_request() {
  local request_path="$1"
  local default_fixture="$2"
  local target_url="$3"
  local scan_profile="$4"

  python3 - "$request_path" "$default_fixture" "$target_url" "$scan_profile" <<'PY'
import json
import os
import sys
import tempfile

request_path = sys.argv[1]
default_fixture = os.path.normpath(sys.argv[2])
default_target = sys.argv[3]
default_scan = sys.argv[4]

normalized_request_path = os.path.normpath(request_path)
if not os.path.isfile(request_path):
    print(f"ERROR: REQUEST_PATH not found: {request_path}", file=sys.stderr)
    sys.exit(2)

with open(request_path, "r", encoding="utf-8") as f:
    data = json.load(f)

target_url = data.get("target_url")
scan_profile = data.get("scan_profile")
is_target_placeholder = target_url == "__TARGET_URL__"
is_scan_placeholder = scan_profile == "__SCAN_PROFILE__"

if is_target_placeholder or is_scan_placeholder:
    if normalized_request_path != default_fixture:
        print(
            "ERROR: REQUEST_PATH contains unresolved placeholders "
            "(__TARGET_URL__ and/or __SCAN_PROFILE__). "
            "Use real values or use the bundled default fixture.",
            file=sys.stderr,
        )
        sys.exit(3)

    if is_target_placeholder:
        data["target_url"] = default_target
    if is_scan_placeholder:
        data["scan_profile"] = default_scan

    fd, tmp_path = tempfile.mkstemp(prefix="site_auditor_v3_request_", suffix=".json")
    os.close(fd)
    with open(tmp_path, "w", encoding="utf-8") as out:
        json.dump(data, out, indent=2)
        out.write("\n")
    print(tmp_path)
    sys.exit(0)

if target_url in (None, ""):
    data["target_url"] = default_target
if scan_profile in (None, ""):
    data["scan_profile"] = default_scan

if data.get("target_url") != target_url or data.get("scan_profile") != scan_profile:
    fd, tmp_path = tempfile.mkstemp(prefix="site_auditor_v3_request_", suffix=".json")
    os.close(fd)
    with open(tmp_path, "w", encoding="utf-8") as out:
        json.dump(data, out, indent=2)
        out.write("\n")
    print(tmp_path)
else:
    print(request_path)
PY
}

REQUEST_EFFECTIVE="$(prepare_request "$REQUEST_INPUT" "$BUNDLED_PLACEHOLDER_FIXTURE" "$DEFAULT_TARGET_URL" "$DEFAULT_SCAN_PROFILE")"
if [ "$REQUEST_EFFECTIVE" != "$REQUEST_INPUT" ]; then
  TMP_REQUEST="$REQUEST_EFFECTIVE"
  echo "INFO: Normalized request fixture for validator run: $REQUEST_INPUT"
fi

cleanup() {
  if [ -n "$TMP_REQUEST" ] && [ -f "$TMP_REQUEST" ]; then
    rm -f "$TMP_REQUEST"
  fi
}
trap cleanup EXIT

echo "=== CLEAN RUNS ==="
rm -rf "$RUNS"/* 2>/dev/null || true

echo "=== RUN AGENT ==="
pwsh -NoProfile -File "$ROOT/run.ps1" \
  -RequestPath "$REQUEST_EFFECTIVE"

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

echo "=== VALIDATE ARCHITECTURE GUARD ==="
RUN_REPORT_PATH="$LATEST_REPORT" python3 "$ROOT/tests/guard_v3_architecture.py"

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
operator_control = get(["operator_control"], {}) or {}
operator_control_keys = ", ".join(operator_control.keys()) if isinstance(operator_control, dict) else "MISSING"

print("read_full_report:", p)
print("full_control_book:", "RUN_REPORT.json -> operator_control")
print("operator_control_keys:", operator_control_keys)
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

echo "=== WRITE ARTIFACT MANIFEST (WRAPPER RUN) ==="
python3 - "$RUN_DIR" "$RUN_ID" <<'PY'
import datetime as dt
import json
import os
import sys

run_dir, run_id = sys.argv[1], sys.argv[2]
deliverable = os.path.abspath(os.path.join("agents/site_auditor_v3/_deliver", f"SITE_AUDITOR_V3_RUNPACK_{run_id}.zip"))
expected_files = ["RUN_REPORT.json", "TASK.json"]

produced_files = []
for name in sorted(os.listdir(run_dir)):
    full = os.path.join(run_dir, name)
    if os.path.isfile(full):
        produced_files.append(name)

missing_expected_files = [name for name in expected_files if name not in produced_files]
extra_files = [name for name in produced_files if name not in expected_files]

manifest = {
    "run_id": run_id,
    "run_dir": os.path.abspath(run_dir),
    "packaging_mode": "WRAPPER_RUN",
    "deliverable": deliverable,
    "produced_files": produced_files,
    "expected_files": expected_files,
    "missing_expected_files": missing_expected_files,
    "extra_files": extra_files,
    "created_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}

with open(os.path.join(run_dir, "ARTIFACT_MANIFEST.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

if command -v zip >/dev/null 2>&1; then
  (cd "$RUN_DIR" && zip -qr "$(cd ../../_deliver && pwd)/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.zip" .)
else
  tar -czf "$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz" -C "$RUN_DIR" .
  ZIP_PATH="$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz"
fi

echo "=== UPDATE RUN_REPORT PACKAGING MODE ==="
python3 - "$LATEST_REPORT" "$ZIP_PATH" <<'PY'
import json, sys
report_path, deliverable = sys.argv[1], sys.argv[2]
with open(report_path, 'r', encoding='utf-8') as f:
    report = json.load(f)

manifest_path = report_path.replace("RUN_REPORT.json", "ARTIFACT_MANIFEST.json")
manifest = {}
with open(manifest_path, 'r', encoding='utf-8') as f:
    manifest = json.load(f)

report["packaging"] = {
    "mode": "WRAPPER_RUN",
    "runpack_expected": True,
    "runpack_created": True,
    "deliverable": deliverable,
    "manifest": "ARTIFACT_MANIFEST.json",
    "produced_files_count": len(manifest.get("produced_files", [])),
    "missing_expected_files": manifest.get("missing_expected_files", []),
    "note": "Validation wrapper created runpack ZIP."
}
with open(report_path, 'w', encoding='utf-8') as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY

echo "DELIVERABLE=$ZIP_PATH"
echo "PASS: END-TO-END"
