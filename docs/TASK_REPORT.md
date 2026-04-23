## Summary
Updated `ROUTE_SELECTION` failure handling in `agents/site_auditor_v2/agent.ps1` to remove script-level `return` exits and route failures through the existing global `try/catch` path. Added explicit fail markers and fail-state assignments for `NO_ROUTES_AVAILABLE` and `EMPTY_ROUTE_SET`, then throw to preserve standard artifact generation flow.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Modified scope is limited to `ROUTE_SELECTION` fail handling branches only.

## Risks/blockers
- No runtime execution was performed in this task, so artifact generation behavior should be validated in CI/runtime with empty/missing routes inputs.
- `throw` now intentionally depends on existing global error handling to produce `RUN_REPORT.json` and failure artifacts.
