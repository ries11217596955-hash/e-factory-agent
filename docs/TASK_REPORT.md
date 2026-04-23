## Summary
Adjusted `ROUTE_SELECTION` input binding in `agents/site_auditor_v2/agent.ps1` so selection now binds directly to the actual `Get-ShallowRoutes()` output object via `$routeExtraction.routes`, then normalizes with `@(...)` before guards. Added explicit bind markers (`BIND_INPUT_START`, `BIND_INPUT_OK count=<N>`) and updated the no-routes guard to throw only after this direct binding.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Functional change limited to `ROUTE_EXTRACTION` output handoff and `ROUTE_SELECTION` input binding/guard logging.

## Risks/blockers
- No live run was executed in this task, so runtime confirmation of the new bind markers and non-zero route count is pending next pipeline run.
- If `Get-ShallowRoutes()` returns a schema without `.routes`, the new explicit binding guard will fail fast with a clear message.
