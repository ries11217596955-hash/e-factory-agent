## Summary
Hardened final visual target selection in `Get-VisualTargets` for PowerShell 5.1 by validating merged ranked targets, guarding empty post-validation collections, selecting safely with array materialization, and returning only an array of selected targets with new route-selection markers.

## Changed files
- agents/site_auditor_v2/modules/stage_route_keys.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Change scope limited to final selection block inside `Get-VisualTargets` in `agents/site_auditor_v2/modules/stage_route_keys.ps1`.

## Risks/blockers
- No full orchestrator run was executed here; runtime verification of marker ordering and downstream consumers expecting array-only return should be validated in integration execution.
