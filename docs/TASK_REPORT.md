## Summary
- Applied a focused fix in `Build-DecisionLayer` to hard-normalize `$normalizedMissingInputs` using `Convert-ToObjectArraySafe` and per-item string coercion.
- Added filtering to keep only non-empty/non-whitespace strings in `$normalizedMissingInputs`.
- Added explicit final-shape enforcement to guarantee non-null array form for `$normalizedMissingInputs`.
- Left `priority_route_sort`, collection handling, and broader `Build-DecisionLayer` logic unchanged per scope constraints.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Modified section: `Build-DecisionLayer` input normalization block for `$normalizedMissingInputs`.

## Risks/blockers
- Full end-to-end runtime validation (cloud/batch execution) was not run in this environment.
- Change is intentionally narrow; behavior outside missing-input normalization is untouched.
