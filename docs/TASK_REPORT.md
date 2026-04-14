## Summary
- Hardened `Build-DecisionLayer` warnings materialization so warnings are always normalized to `string[]` before downstream processing.
- Updated the `Build-DecisionLayer` warnings parameter contract to accept incoming mixed types and coerce safely via `Convert-ToStringSafe`.
- Added explicit null handling for warnings (`$warnings = @()` when null) before normalization.
- Added final string enforcement pass to prevent mixed-type warning payloads.
- Kept all changes scoped to Build-DecisionLayer logic and task reporting only.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry script remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Decision-core changes are limited to `Build-DecisionLayer` warnings normalization flow.

## Risks/blockers
- `pwsh` is unavailable in this container, so end-to-end DECISION_BUILD execution could not be validated here.
- Runtime outcomes still depend on executing the agent in the target environment with real input payloads.
