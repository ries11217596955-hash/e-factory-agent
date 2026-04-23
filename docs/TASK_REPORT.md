## Summary
Restored the `Get-VisualTargets` structured return contract for PowerShell 5.1 stage handoff stability by returning `selected_routes`, `overflow_routes`, and `selection_strategy` while preserving existing ranking/selection behavior and route-selection markers.

## Changed files
- agents/site_auditor_v2/modules/stage_route_keys.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Change scope limited to `Get-VisualTargets` return-shape block in `agents/site_auditor_v2/modules/stage_route_keys.ps1`.

## Risks/blockers
- No full end-to-end run was executed in this environment; integration execution should confirm downstream CAPTURE stage continuation with restored properties.
