## Summary
- Applied a targeted output-sanitization fix inside `Build-DecisionLayer` to prevent ordered hashtable type crashes at return time.
- Added a SAFE NORMALIZATION LAYER immediately before return, coercing decision output fields to deterministic string/array-of-string shapes.
- Normalized `STAGE`, `CORE_PROBLEM`, `P0`, `P1`, `P2`, `DO_NEXT`, and `MISSING` values with null-safe iteration and string casting.
- Replaced the function return with `return [ordered]$decision` to emit an ordered hashtable built from sanitized values only.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Modified scope: `Build-DecisionLayer` final output/return block only.

## Risks/blockers
- Full DECISION_BUILD end-to-end execution was not run in this environment, so runtime confirmation depends on CI/operator execution.
- Sanitized output now returns the normalized decision envelope (`STAGE`, `CORE_PROBLEM`, `P0`, `P1`, `P2`, `DO_NEXT`, `MISSING`) and may reduce availability of previous auxiliary keys if downstream consumers relied on them.
