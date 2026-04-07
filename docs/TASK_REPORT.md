## Summary
Fixed a SITE_AUDITOR runtime crash in REPO/ZIP flows by normalizing `sourceLayer` shape so `base_url` is always present. Added a `New-SourceLayer` normalizer and updated `Invoke-SourceAuditRepo` / `Invoke-SourceAuditZip` returns to include `base_url = $null` while preserving routing and FAIL/decision logic.

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
- Did not change mode-routing, status decisioning, or failure criteria; this patch is structural normalization only.
