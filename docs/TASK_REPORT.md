## Summary
- Fixed REPORT_LAYER consistency-lock failures by guaranteeing `operator_memory_bridge.status_detail` is populated before lock assertions execute.
- Added deterministic status-detail mapping based on canonical values only: `PASS`, `PASS_WITH_LIMITS`, `FAIL`.
- Implemented required mapping rules from `RUN_REPORT.status` and `audit_confidence`:
  - `PASS` + `LOW` → `PASS_WITH_LIMITS`
  - `PASS` + not `LOW` → `PASS`
  - `FAIL` → `FAIL`
- Kept operator-control guard behavior intact by leaving all existing consistency-lock required-field checks in place.
- Limited scope strictly to allowed files.

## Changed files
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Consistency lock entrypoint remains `Test-ReportConsistencyLock` in `agents/site_auditor_v2/modules/report_layer.ps1`.
- Status-detail population now occurs via `Set-OperatorMemoryBridgeStatusDetail -Report $Report` at the start of `Test-ReportConsistencyLock`.
- Output/report flow remains unchanged; `RUN_REPORT.json` production/inclusion is still managed by existing agent/report pipeline (no path or routing modifications in this task).

## Risks/blockers
- Validation here is code-level and focused on consistency-lock preparation logic; no full live SITE_AUDITOR_V2 audit run was executed in this environment.
- For non-canonical/unknown `RUN_REPORT.status` values, fallback is currently `FAIL` to preserve deterministic canonical output and avoid missing `status_detail`.
