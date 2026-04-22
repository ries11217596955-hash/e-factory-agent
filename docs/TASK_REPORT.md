## Summary
Implemented reconciliation as the final authority for RUN_REPORT status controls in LINK mode. Final `capture_report.status`, `execution_status`, and `decision_allowed` are now derived strictly from `evidence_reconciliation.status`, with explicit hard-fail behavior when reconciliation fails or does not execute.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent runtime entrypoint: `agents/site_auditor_v2/agent.ps1`
- Visual capture tool: `agents/site_auditor_v2/tools/capture_visuals.mjs`
- Reconciliation authority output fields in `RUN_REPORT.json`:
  - `capture_report.status`
  - `execution_status`
  - `decision_allowed`
  - `trust_boundary`

## Risks/blockers
- `pwsh` is not available in this execution environment, so runtime validation scenarios could not be executed end-to-end locally.
- `status` now allows `PARTIAL` in the schema; downstream consumers expecting only PASS/FAIL may need to handle the additional value.
