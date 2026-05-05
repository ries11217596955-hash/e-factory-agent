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
LATEST_REPORT="$(ls -1dt $RUNS/* 2>/dev/null | head -n1)/RUN_REPORT.json"
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
python3 - <<PY
import json, sys
p = "$LATEST_REPORT"
j = json.loads(open(p).read())
print("run_id:", j["identity"]["run_id"])
print("verdict:", j["audit_result"]["verdict"])
print("score:", j["audit_result"]["score"])
print("next_capability:", j["agent_capability_state"]["next_capability_to_build"])
print("limitations:", j["diagnostic_summary"]["limitations"])
PY


echo "=== PACKAGE RUNPACK ==="
DELIVER_ROOT="$ROOT/_deliver"
mkdir -p "$DELIVER_ROOT"

RUN_DIR="$(dirname "$LATEST_REPORT")"
RUN_ID="$(basename "$RUN_DIR")"
ZIP_PATH="$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.zip"

if command -v zip >/dev/null 2>&1; then
  (cd "$RUN_DIR" && zip -qr "../../_deliver/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.zip" .)
else
  tar -czf "$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz" -C "$RUN_DIR" .
  ZIP_PATH="$DELIVER_ROOT/SITE_AUDITOR_V3_RUNPACK_${RUN_ID}.tar.gz"
fi

echo "DELIVERABLE=$ZIP_PATH"

echo "PASS: END-TO-END"
