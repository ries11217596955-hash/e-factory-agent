## Summary
- Task: SITE_AUDITOR repair batch to preserve runtime failure context and prevent degradation to generic `Unknown failure` output.
- Captured catch-path forensic context (active operation label, failing function hint, exception message, script stack) in the main execution catch block.
- Updated failure-message propagation so real exception text is preferred and generic fallback is only used when no concrete message exists.
- Preserved explicit failing node context in run forensics by promoting `decision_build_failed_node` into `failure_node` when the stage would otherwise collapse to `OPERATOR_OUTPUT_CONTRACT`/`RUNTIME_FAILURE`.
- Kept scope minimal: no decision logic, page quality logic, workflow, or architecture refactor changes.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Runtime failure wrapping adjusted in main catch path near end of `agent.ps1`.
- Failure node projection adjusted in `Write-RunForensicsReports` within `agent.ps1`.

## Risks/blockers
- Could not execute a full PowerShell runtime verification in this container because `pwsh` is not available.
- Validation should be confirmed in next SITE_AUDITOR run by checking `RUN_REPORT.json` / `FAILURE_SUMMARY.json` for non-generic `error_message` and explicit non-collapsed failure node values.
