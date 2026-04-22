## Summary
Added minimal per-page actions to `problem_targets`, generated `ACTION_SUMMARY.json`, updated `RUN_REPORT` artifact lists to include `ACTION_SUMMARY.json`, and set handoff `next_task_shape` to `refine actions only`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- New artifact output: `ACTION_SUMMARY.json`
- Updated run report outputs: `RUN_REPORT.json -> produced_artifacts`, `RUN_REPORT.json -> linked_artifacts`
- Updated handoff field: `RUN_REPORT.json -> operator_handoff.next_task_shape`

## Risks/blockers
- None.
