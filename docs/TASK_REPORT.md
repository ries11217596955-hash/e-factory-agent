## Summary
- Enforced `Build-DecisionLayer` warnings final materialization as a pure `string[]` immediately before decision return.
- Added a defensive non-array guard (`if ($warnings -isnot [System.Array]) { $warnings = @($warnings) }`) in `Build-DecisionLayer`.
- Added null-safe final casting for every warning entry (`$null` becomes `''`, all others become `[string]`).
- Materialized `warnings` on the final decision object using array syntax (`warnings = @($warnings)`).
- Kept scope limited to `Build-DecisionLayer` and task reporting.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Only `Build-DecisionLayer` warning normalization/materialization path was changed.

## Risks/blockers
- `pwsh` is not available in this container, so runtime execution validation for this PowerShell path could not be run locally.
- Functional verification should be completed in an environment with PowerShell available.
