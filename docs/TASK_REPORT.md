## Summary
Implemented an observability-only label coverage fix in `Build-DecisionLayer` so downstream failures are attributed to the true failing node instead of a stale `contradiction_summary_build` label.
- Added explicit `activeOperationLabel` + `activeExpression` assignments immediately before each critical downstream call in the decision build sequence.
- Preserved existing call order, inputs, outputs, and status behavior (`FAIL` path unchanged).
- No business logic, contradiction logic, Count handling, helper conversion behavior, or control-flow refactor was changed.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Decision layer observability labels updated: `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- Task report updated: `docs/TASK_REPORT.md`

## Risks/blockers
- Runtime execution was not performed in this patch task, so validation of the next failing label requires the next pipeline run.
- If any called function throws before internal safeguards, attribution should now point to the specific pre-call label added for that node.
