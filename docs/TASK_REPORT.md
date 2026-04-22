## Summary
Updated `agents/site_auditor_v2/agent.ps1` to mirror generated artifacts from the run-scoped output directory into deterministic top-level paths so required files are always available at stable locations. `RUN_REPORT.json` is now always copied to `agents/site_auditor_v2/RUN_REPORT.json`, and `failure_summary.json` is copied to `agents/site_auditor_v2/failure_summary.json` on FAIL runs.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- RUN_REPORT output path: `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
- Deterministic RUN_REPORT mirror path: `agents/site_auditor_v2/RUN_REPORT.json`
- Failure summary output path (on fail): `agents/site_auditor_v2/output/<run_id>/failure_summary.json`
- Deterministic failure summary mirror path (on fail): `agents/site_auditor_v2/failure_summary.json`

## Risks/blockers
- No blockers identified.
- Deterministic mirror files are overwritten on each run by design to ensure predictable artifact lookup.
