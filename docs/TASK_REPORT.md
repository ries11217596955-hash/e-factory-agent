## Summary
Implemented LINK-mode route normalization before visual capture so equivalent routes resolve to one canonical key (`normalized_route`) and deduplicate to one logical page. Added fallback behavior that preserves original routes on normalization errors and marks `route_normalization` as `failed` in `RUN_REPORT`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent runtime entrypoint: `agents/site_auditor_v2/agent.ps1`
- Route collection path: `Get-ShallowRoutes` (normalization + dedup)
- Visual target selection path: `Get-VisualTargets` (canonical dedup keys)
- Screenshot capture tool (unchanged logic): `agents/site_auditor_v2/tools/capture_visuals.mjs`

## Risks/blockers
- `pwsh` is not available in this execution environment, so end-to-end LINK-mode runtime validation could not be executed locally.
- Path lowercasing is now part of canonicalization; environments with case-sensitive URL routing may intentionally serve different content by path case.
