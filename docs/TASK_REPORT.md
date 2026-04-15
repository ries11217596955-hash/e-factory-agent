## Summary
- Added a force-copy block to `run_bundle.ps1` to always place `report.json` at `agents/gh_batch/site_auditor_cloud/reports/report.json` when any nested `report.json` exists.
- Created the root `reports` directory if it is missing before copy.
- Implemented recursive search for `report.json` under bundle scope and copy of the first match to the root reports target.
- Added explicit host output for both success (`FORCE COPY`) and no-report warning paths.
- Updated this report for `TASK_ID: SITE_AUDITOR_AGENT__FORCE_REPORT_TO_ROOT_REPORTS`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Bundle entry script remains `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Forced output target path is `agents/gh_batch/site_auditor_cloud/reports/report.json`.
- Existing runtime flow, workflow files, and validation logic remain unchanged.

## Risks/blockers
- Recursive search uses the first `report.json` found under `$PSScriptRoot`; if multiple reports exist, selection order depends on filesystem enumeration.
- GitHub Actions runtime verification is not executed in this environment; final confirmation should come from CI logs/artifacts.
