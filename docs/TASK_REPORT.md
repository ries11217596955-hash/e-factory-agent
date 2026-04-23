## Summary
Fixed `Get-VisualTargets()` generic list merge failure in PowerShell 5.1 by explicitly materializing tier lists to arrays before concatenation, then emitting stage markers for merge and overflow readiness without changing ranking/selection semantics.

## Changed files
- agents/site_auditor_v2/modules/stage_route_keys.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Functional change limited to `Get-VisualTargets()` in `agents/site_auditor_v2/modules/stage_route_keys.ps1` around tier merge and overflow materialization.

## Risks/blockers
- No end-to-end pipeline run was executed in this task, so marker visibility (`VISUAL_TARGETS_MERGE_READY`, `VISUAL_TARGETS_OVERFLOW_READY`) and absence of runtime merge errors remain to be verified in the next orchestrator execution.
