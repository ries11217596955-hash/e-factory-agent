## Summary
Fixed `Get-VisualTargets()` list merge safety in `agents/site_auditor_v2/modules/stage_route_keys.ps1` by materializing both tier lists to arrays before concatenation, preventing the Generic.List `+` crash (`Argument types do not match`). Added temporary route-selection markers around merge/overflow preparation: `VISUAL_TARGETS_MERGE_READY` and `VISUAL_TARGETS_OVERFLOW_READY`.

## Changed files
- agents/site_auditor_v2/modules/stage_route_keys.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Functional change limited to `Get-VisualTargets()` merge/overflow preparation in `agents/site_auditor_v2/modules/stage_route_keys.ps1`.

## Risks/blockers
- No end-to-end agent run was executed in this task, so runtime confirmation of expected downstream markers (`BEFORE_SELECT`, `SELECTED_OK`) is pending next run.
- Temporary debug markers were intentionally added and may be removed after validation if no longer needed.
