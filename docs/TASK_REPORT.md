## Summary
- Enforced operator-memory bridge contract fields in the report consistency lock so missing `status_detail`, execution context, next-step, forbidden-steps, and tool guidance now hard-fail the report layer.
- Added explicit `operator_memory_bridge` contract keys (`status_detail`, `current_execution_mode`, `current_layer`, `one_next_step`, `forbidden_next_steps`, `tool_recommendation`) when building `RUN_REPORT`.
- Synced `operator_memory_bridge.status_detail` and `operator_memory_bridge.one_next_step` after final status/next-step resolution to keep the bridge truthful for PASS/PASS_WITH_LIMITS outcomes.
- Added a dedicated artifact check script `tests/check_operator_report_contract.ps1` that fails when REPORT_EN/REPORT_RU lose OPERATOR CONTROL fields or when RUN_REPORT bridge fields are missing.
- Added PASS_WITH_LIMITS guardrails in checks: LIMITATION must include a real explanation and cannot be a "none/not low" placeholder.

## Changed files
- agents/site_auditor_v2/modules/report_layer.ps1
- agents/site_auditor_v2/agent.ps1
- tests/check_operator_report_contract.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- RUN_REPORT consistency gate: `agents/site_auditor_v2/modules/report_layer.ps1` (`Test-ReportConsistencyLock`).
- RUN_REPORT bridge construction: `agents/site_auditor_v2/agent.ps1` (`$report.operator_memory_bridge` assembly/update).
- Operator report contract check: `tests/check_operator_report_contract.ps1`.

## Risks/blockers
- The new operator-report check validates generated artifacts and requires real run output fixtures; repository does not currently include a stable sample output bundle for deterministic CI fixture testing.
- `Invoke-PostOutput` remains wrapped by a safe runtime try/catch in `agent.ps1`, so runtime hard-fail behavior still depends on running this explicit check script in validation pipelines.
