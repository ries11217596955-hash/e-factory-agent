## Summary
- Task: SITE_AUDITOR execution trace integrity repair to stop runtime failures collapsing into generic unknown output.
- Updated main execution catch-path propagation in `agent.ps1` so the original exception message is preserved and combined with a concrete failure node.
- Captured and preserved `failure_stage/function_name/activeOperationLabel` into a stable node string for catch-time reporting.
- Updated decision forensic node projection so `decision_build_failed_node` is emitted even when only stage-level forensic data exists.
- Kept patch scope minimal and non-invasive (no business logic or module behavior changes).

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Failure propagation wrapper in the outer `try/catch` of `agent.ps1` now emits exact exception + forensic failure node.
- `Write-RunForensicsReports` in `agent.ps1` now preserves stage-only decision forensic nodes in `decision_build_failed_node`.

## Risks/blockers
- `pwsh` runtime validation could not be executed in this environment (PowerShell unavailable), so verification is static-only.
- Final confirmation should be done in the next SITE_AUDITOR run by checking `RUN_REPORT.json` / `FAILURE_SUMMARY.json` for:
  - non-generic `error_message`
  - populated `decision_build_failed_node`
  - `failure_node` that reflects the failing module/function/operation.
