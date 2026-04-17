## Summary
Implemented `SA_DONEXT_ARRAY_SHAPE_FIX_002` by coercing `$doNextItems` to a deterministic array shape boundary in `Write-OperatorOutputs`, preserving top-3 selection while preventing scalar-vs-array Count failures.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent execution path: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Updated boundary block: `$doNextItems` assignment and Count fallback in `Write-OperatorOutputs` (`Decision.do_next` top-3 extraction path)

## Risks/blockers
- No end-to-end PowerShell run was executed in this environment, so runtime confirmation should be completed in the next pipeline/agent execution.
