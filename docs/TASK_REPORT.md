## Summary
Tightened SITE_AUDITOR to enforce the mandatory routing contract: REPO now requires both `TARGET_REPO_PATH` and `BASE_URL`, ZIP now requires both ZIP payload and `BASE_URL`, and URL continues to require `BASE_URL`. Removed REPO/ZIP warning-only fallback for missing `BASE_URL`, strengthened decision wording, and expanded report/status outputs to show explicit source/live PASS/FAIL/OFF and required input visibility.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Runtime entrypoint: `agents/gh_batch/site_auditor_cloud/run.ps1`
- Main orchestration + layered audit execution: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- URL capture worker: `agents/gh_batch/site_auditor_cloud/capture.mjs`
- ZIP intake helper: `agents/gh_batch/site_auditor_cloud/lib/intake_zip.ps1`
- ZIP preflight helper: `agents/gh_batch/site_auditor_cloud/lib/preflight.ps1`
- Deterministic ZIP extraction root (runtime): `agents/gh_batch/site_auditor_cloud/runtime/zip_extracted`
- Guaranteed output directories:
  - `agents/gh_batch/site_auditor_cloud/outbox/`
  - `agents/gh_batch/site_auditor_cloud/reports/`
- Guaranteed operator outputs retained:
  - `outbox/REPORT.txt`
  - `outbox/DONE.ok` or `outbox/DONE.fail`
  - `reports/run_manifest.json`
  - `reports/audit_result.json`
  - `reports/HOW_TO_FIX.json`
  - `reports/00_PRIORITY_ACTIONS.txt`
  - `reports/01_TOP_ISSUES.txt`
  - `reports/11A_EXECUTIVE_SUMMARY.txt`

## Risks/blockers
- URL/live auditing still requires Node.js + Playwright availability and reachable target routes.
- ZIP extraction uses platform archive support (`Expand-Archive`); malformed or unsupported archives correctly force FAIL.
- REPO and ZIP now hard-fail when `BASE_URL` is missing; operators must provide all required inputs per mode before execution.
