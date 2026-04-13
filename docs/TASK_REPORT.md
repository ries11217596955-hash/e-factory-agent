# TASK_REPORT

## Summary
- Added a narrow reporting-contract layer in `SITE_AUDITOR_AGENT` so each run now emits a top-level operator-ready forensic report plus machine-readable companion summaries.
- Added `reports/RUN_REPORT.txt` generation with embedded evidence excerpts (source/live/page-quality/product/failure context), artifact guidance, and explicit next technical move.
- Added `reports/RUN_REPORT.json`, `reports/ARTIFACT_MANIFEST.json`, and status-gated `reports/FAILURE_SUMMARY.json`/`reports/SUCCESS_SUMMARY.json` for automation.
- Added run metadata surfacing (`run_id`, `started_at`, `finished_at`, `final_stage`, `last_success_stage`) and carried those fields into report/manifest outputs.
- Added fallback contract generation in `Ensure-OutputContract` so the new report files still exist even when primary report emission fails.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Unchanged entrypoints:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- New operator-report contract outputs emitted under:
  - `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json`
  - `agents/gh_batch/site_auditor_cloud/reports/ARTIFACT_MANIFEST.json`
  - `agents/gh_batch/site_auditor_cloud/reports/FAILURE_SUMMARY.json` (or `SUCCESS_SUMMARY.json` on PASS)

## Risks/blockers
- Environment does not include `pwsh`, so direct PowerShell parse/runtime validation could not be executed here.
- Changes are intentionally constrained to reporting/forensics surfacing and output contract generation; source/live/page-quality decision logic was not redesigned.
