## Summary
- Fixed `Build-DecisionLayer` priority-route candidate collection initialization to use `System.Collections.ArrayList` so `.Add()` accepts PSCustomObject consistently.
- Updated candidate insertion to use `[void]` cast on `.Add()` and enforced `[string]`/`[int]` field typing at insertion time.
- Added an explicit pre-sort shape enforcement step: `$priorityRouteCandidates = @($priorityRouteCandidates)` before the `priority_route_sort` block.
- Kept sorting logic unchanged and did not modify summary/runReport behavior.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Modified decision-layer location: `Build-DecisionLayer` priority route candidate collection and pre-sort preparation.

## Risks/blockers
- Runtime validation of the full cloud batch flow was not executed in this environment; changes were limited to type-safe collection handling in the targeted block.
