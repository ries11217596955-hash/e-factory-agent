## Summary
Implemented the real SITE_AUDITOR routing contract with unified source/live/decision layering and honest FAIL behavior: REPO now supports REPO+URL, ZIP now performs real extraction/inventory plus optional URL audit, and URL remains live-only with required visual evidence.

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
- REPO/ZIP without BASE_URL intentionally remains source-only and is surfaced as an explicit warning in decision outputs.
