# TASK_REPORT

## Summary
- Task: SITE_AUDITOR — NORMALIZE-LIVEROUTES LINE-617 SURGICAL FORENSICS.
- INSTRUCTION_FILES_READ: `AGENTS.md`, `docs/README.md`, `docs/REPO_LAYOUT.md`.
- FAILURE_FUNCTION: `Normalize-LiveRoutes`.
- FAILURE_LINE_REGION: `agents/gh_batch/site_auditor_cloud/agent.ps1` line region 621-673 (post-loop return/dropped-count computation near reported line 617).
- OPERATION_LABEL: Instrumented as `OP1_raw_route_count`, `OP2_normalized_count`, `OP3_count_subtraction`, `OP4_math_max_dropped_count`.
- EXACT_EXPRESSION: Captured per operation as `@($rawRoutes).Count`, `$normalized.Count`, `$rawRouteCount - $normalizedCount`, and `[int]([Math]::Max(0, $droppedDelta))`.
- LEFT_TYPE: Runtime-captured via `Set-RouteNormalizationForensics.left_type` (no placeholders in instrumentation path).
- RIGHT_TYPE: Runtime-captured via `Set-RouteNormalizationForensics.right_type` (no placeholders in instrumentation path).
- SAMPLE_VALUES: Runtime-captured via `left_value_sample`, `right_value_sample`, `variable_names`, `context_keys`, and `route_path_if_available`.
- FIX_APPLIED: Added operation-level micro-instrumentation around each suspicious return-region operation, and extended forensic payload to include `operation_label` + `variable_names` for exact fault localization.
- VALIDATION_RESULT: Static change validation completed; runtime validation blocked because PowerShell runtime (`pwsh`/`powershell`) is unavailable in this container.
- NEXT_BLOCKER_IF_ANY: Cannot execute `agent.ps1` locally to produce fresh `reports/route_normalization_debug.json` evidence without PowerShell.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Invocation wrapper unchanged: `agents/gh_batch/site_auditor_cloud/run.ps1`
- Debug artifact target unchanged: `agents/gh_batch/site_auditor_cloud/reports/route_normalization_debug.json`

## Risks/blockers
- Blocker: PowerShell is not installed in this execution environment, so exact failing operation could not be empirically confirmed against a fresh bundle in-container.
- Risk: Until a PowerShell-capable run is executed, root-cause confirmation remains pending despite full operation-level capture instrumentation.
