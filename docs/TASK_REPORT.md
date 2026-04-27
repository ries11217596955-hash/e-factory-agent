## Summary
- Added primary-route canonical normalization helpers in `agent.ps1` to enforce path-only identities (no query, no fragment, no trailing slash except root) before REPORT_LAYER contract validation.
- Applied normalization to all primary route identity fields validated by the route contract: `selected_routes.route`, `page_verdicts.route`, `run_budget.overflow_route_details[].route`, `visual_manifest.pages[].route`, and `ROUTES_SUMMARY.routes[].normalized_route`.
- Updated the `ROUTE_CONTRACT_BREACH` failure path to force `ACTION_SUMMARY.json.status = "FAIL"` and set an explicit failure reason so it does not remain `LIMITATION_ONLY` when `RUN_REPORT` fails.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator entrypoint: `agents/site_auditor_v2/agent.ps1`
- Route normalization and contract check callsite: `agents/site_auditor_v2/agent.ps1` (`REPORT_LAYER` section, pre-`Test-RouteContract`)
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Could not execute end-to-end PowerShell validation in this container because `pwsh` is unavailable, so acceptance verification (`ROUTE_CONTRACT_BREACH` disappearance in live run artifacts) must be confirmed in the target runtime environment.
