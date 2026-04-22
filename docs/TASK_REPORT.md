## Summary
Updated operator handoff in LINK mode so the next task is action-driving and tied to current audit results. Added dynamic `primary_problem` and specific `next_task_shape` selection based on `thin`, `broken`, and `ok` counts from route classifications, and replaced generic pre-task checks with explicit route/content checks.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Operator handoff block: `RUN_REPORT.json -> operator_handoff`
- Focus files emitted by audit flow: `ROUTES_SUMMARY.json`, `AUDIT_SUMMARY.json`

## Risks/blockers
- If route sampling under-represents site depth, dominant-problem detection may prioritize the wrong next task.
- Threshold-based classification can still skew counts that drive `primary_problem` selection.
