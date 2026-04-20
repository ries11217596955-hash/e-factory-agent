## Summary
Applied a compatibility-first truth-layer hardening update for site auditor failure outputs. The change stabilizes shared failure facts (message/class) across `RUN_REPORT.json` and `FAILURE_SUMMARY.json`, and mirrors `outbox/REPORT.txt` into `reports/REPORT.txt` when present so bundle-side artifact inclusion remains deterministic.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Runtime truth artifacts remain at:
  - `reports/RUN_REPORT.json`
  - `reports/FAILURE_SUMMARY.json` (FAIL/PARTIAL)
  - `outbox/REPORT.txt` (runtime operator report)
  - `reports/REPORT.txt` (mirror copy when runtime report exists)

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this container (`pwsh` not installed), so runtime execution checks could not be run locally.
- Risk: success-check assertions for `failed_step=PAGE_QUALITY_BUILD` and bundle-side inclusion must be verified on the workflow runner that executes `run.ps1`/`run_bundle.ps1`.
