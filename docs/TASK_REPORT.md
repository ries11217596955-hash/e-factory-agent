## Summary
- Replaced the `priority_route_sort` candidate normalization output fields with explicit `[string]`/`[int]` typed values to eliminate mixed-type sort inputs.
- Replaced the multi-property `Sort-Object -Property ...` call with scriptblock-based sort keys for deterministic severity-desc/route-asc ordering.
- Preserved existing Build-DecisionLayer flow, decision summary behavior, and runReport formatting outside the priority sort cluster.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Patched decision block location: Build-DecisionLayer `priority_route_sort` cluster in `agents/gh_batch/site_auditor_cloud/agent.ps1`.

## Risks/blockers
- Full `DECISION_BUILD` runtime validation depends on executing the complete Site Auditor pipeline inputs; this environment verified the patch statically but did not run a full cloud batch audit cycle.
