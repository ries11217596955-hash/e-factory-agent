#!/usr/bin/env bash
set -euo pipefail

ROOT="agents/site_auditor_v3"

echo "=== SUITE: ROOT SMOKE ==="
REQUEST_PATH="$ROOT/tests/fixtures/smoke.request.json" \
"$ROOT/tests/run_and_validate.sh"

echo "=== SUITE: DEEP LINK ==="
REQUEST_PATH="$ROOT/tests/fixtures/deep-link.request.json" \
"$ROOT/tests/run_and_validate.sh"

echo "PASS: V3 SUITE"
