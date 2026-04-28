## Summary
- Replaced the narrow `Set-OperatorMemoryBridgeStatusDetail` helper with `Ensure-OperatorMemoryBridgeRequiredFields` so all consistency-lock-required `operator_memory_bridge` fields are populated before assertions.
- Preserved canonical status-detail mapping (`PASS`, `PASS_WITH_LIMITS`, `FAIL`) using `RUN_REPORT.status` and `audit_confidence`.
- Added safe defaults for bridge control fields: execution mode, layer metadata, next artifact path, reason to inspect, one next step, forbidden steps array, and tool guidance.
- Kept strict consistency-lock guard behavior intact; no required-field assertion was removed or weakened.
- Limited scope strictly to allowed files.

## Changed files
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Consistency lock entrypoint remains `Test-ReportConsistencyLock` in `agents/site_auditor_v2/modules/report_layer.ps1`.
- Required operator bridge population now occurs via `Ensure-OperatorMemoryBridgeRequiredFields -Report $Report -LimitationCount $LimitationCount` at the start of `Test-ReportConsistencyLock`.
- Output/report flow remains unchanged; `RUN_REPORT.json` production/inclusion is still managed by existing agent/report pipeline (no path or routing modifications in this task).

## Risks/blockers
- Validation here is code-level and focused on consistency-lock preparation logic; no full live SITE_AUDITOR_V2 audit run was executed in this environment.
- If `run_id` is missing, helper intentionally falls back to `RUN_REPORT.json` for `next_file_to_inspect` to keep the bridge non-empty and deterministic.
