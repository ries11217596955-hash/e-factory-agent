## Summary
- Hardened generated `AGENT_MAP.md` content to include an explicit layer contract map for ROUTE_LAYER, CAPTURE_LAYER, RECON_LAYER, REPORT_LAYER, and OUTPUT_LAYER.
- Added owner file, purpose, inputs, outputs, and failure signals per layer so operators can locate code ownership without browsing the repository.
- Extended `RUN_REPORT.operator_memory_bridge` payload generation with `layer_owner_file`, `next_file_to_inspect`, and `reason_to_inspect`, while keeping `current_layer` explicit.
- Enforced new operator bridge fields in the report consistency lock to fail fast when handoff ownership metadata is missing.
- Updated `run_report.schema.json` so the added bridge keys are part of the contract required set.

## Changed files
- agents/site_auditor_v2/contracts/run_report.schema.json
- agents/site_auditor_v2/modules/report_layer.ps1
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- AGENT_MAP generation: `agents/site_auditor_v2/agent.ps1` (`# === STAGE: AGENT_MAP ===` block).
- RUN_REPORT bridge construction: `agents/site_auditor_v2/agent.ps1` (`$report.operator_memory_bridge` assembly/update).
- RUN_REPORT consistency gate: `agents/site_auditor_v2/modules/report_layer.ps1` (`Test-ReportConsistencyLock`).
- RUN_REPORT schema ownership contract: `agents/site_auditor_v2/contracts/run_report.schema.json` (`operator_memory_bridge` required keys).

## Risks/blockers
- Layer owner/failure signal text in `AGENT_MAP.md` is generated documentation and must stay synchronized with implementation files if stage ownership changes later.
- No full agent run was executed in this task, so acceptance of "current green run remains green" relies on static contract updates and existing runtime behavior.
