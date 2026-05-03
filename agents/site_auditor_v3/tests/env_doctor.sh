#!/usr/bin/env bash
set -e

echo "=== ENV DOCTOR ==="
echo "PWD=$(pwd)"
echo "BRANCH=$(git branch --show-current)"
echo "LOCAL=$(git rev-parse HEAD)"
echo "REMOTE=$(git rev-parse origin/main 2>/dev/null || echo NO_REMOTE)"

echo "=== TOOLS ==="
for t in git pwsh python3 python node npm; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "OK $t $(command -v "$t")"
  else
    echo "MISSING $t"
  fi
done

echo "=== V3 ENTRY FILES ==="
test -f agents/site_auditor_v3/run.ps1 && echo "OK run.ps1" || echo "MISSING run.ps1"
test -f agents/site_auditor_v3/tests/guard_v3_build.py && echo "OK guard" || echo "MISSING guard"
test -f agents/site_auditor_v3/tests/fixtures/smoke.request.json && echo "OK smoke fixture" || echo "MISSING smoke fixture"
