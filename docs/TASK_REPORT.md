## Summary
- Applied strict trace-hardening updates for SITE_AUDITOR runtime failure propagation so exception text and failing node context are preserved end-to-end.
- Removed generic unknown-failure fallbacks from report/fallback paths and replaced them with exception-derived message defaults.
- Updated top-level catch handling to capture `$currentNode` from `activeOperationLabel` before composing failure output, then persist node into failure reason text.
- Ensured `decision_build_failed_node` is preserved from existing report evidence and backfilled from resolved failed stage when absent (no empty reset).
- Kept scope minimal to requested runtime trace path and reporting artifact update.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Hardened failure propagation is in the outer `catch` block and run-report generation helpers within `agents/gh_batch/site_auditor_cloud/agent.ps1`.

## Risks/blockers
- PowerShell runtime parse/execute verification could not be run because `pwsh` is unavailable in this container.
- Validation is static and should be confirmed in next production run by checking `RUN_REPORT.json` and fallback outputs for:
  - exact exception message retention
  - populated `failure_node`
  - non-empty `decision_build_failed_node`
  - absence of `Unknown fallback failure.`
