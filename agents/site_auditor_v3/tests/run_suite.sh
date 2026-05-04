#!/usr/bin/env bash
set -euo pipefail

ROOT="agents/site_auditor_v3"

echo "=== SUITE: ROOT SMOKE ==="
REQUEST_PATH="$ROOT/tests/fixtures/smoke.request.json" \
"$ROOT/tests/run_and_validate.sh"

ROOT_REPORT=$(ls -1dt $ROOT/runs/* | head -n1)/RUN_REPORT.json

echo "ROOT SUMMARY:"
python3 - <<PY
import json
j=json.load(open("$ROOT_REPORT"))
print(j["audit_result"]["verdict"], j["audit_result"]["score"], j["diagnostic_summary"]["limitations"])
PY

echo "=== SUITE: DEEP LINK ==="
REQUEST_PATH="$ROOT/tests/fixtures/deep-link.request.json" \
"$ROOT/tests/run_and_validate.sh"

DEEP_REPORT=$(ls -1dt $ROOT/runs/* | head -n1)/RUN_REPORT.json

echo "DEEP SUMMARY:"
python3 - <<PY
import json
j=json.load(open("$DEEP_REPORT"))
print(j["audit_result"]["verdict"], j["audit_result"]["score"], j["diagnostic_summary"]["limitations"])
PY

echo "PASS: V3 SUITE"
