## Summary
- Root cause classified as **missing RUN_REPORT writer + wrong output root** in `run_bundle.ps1`.
- Normalized bundle SSOT output to `reports/` by making the bundle root canonical and writing all bundle-level outputs there.
- Added an explicit RUN_REPORT writer (`Write-RunReportJson`) and integrated it into success and failure writing paths.
- Added a strict pre-validation guard that auto-generates fallback `reports/RUN_REPORT.json` when missing.
- Added a dedicated validation stage that validates only `reports/RUN_REPORT.json` and removed legacy forced `report.json` copy behavior.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Canonical validation/report root: `agents/gh_batch/site_auditor_cloud/reports/`
- Canonical required contract artifact: `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json`
- Legacy debug mirror remains available: `agents/gh_batch/site_auditor_cloud/audit_bundle/` (non-SSOT)

## Risks/blockers
- Runtime execution test is blocked because PowerShell (`pwsh`/`powershell`) is not installed in this environment.
- Negative-path behavior was validated by code-path inspection and guard placement, not by executing full PowerShell pipeline locally.
