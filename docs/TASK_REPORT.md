## Summary
- Implemented SITE_SCOPE_DISCOVERY_PACK v0.1 in the existing route discovery owner flow by upgrading `Invoke-RouteDiscoveryInternal` to fuse baseline candidates, root links, sitemap routes, and recursive same-host HTML crawl with depth/limit controls.
- Added explicit route classification (`page_routes`, `asset_routes`, `rejected_routes`) and scope truth fields (`discovery_sources`, `scope_status`, `scope_reason`, truncation-aware partial scope semantics).
- Updated route feedback/promotion contracts so only page-like routes are promoted while asset-like routes are excluded and counted.
- Expanded RUN_REPORT route_feedback fallback/output contract to include richer scope truth defaults.
- Extended Python validators to enforce the new route scope truth and asset-exclusion contracts.

## Changed files
- `agents/site_auditor_v3/modules/internal_command_handlers.ps1`
- `agents/site_auditor_v3/modules/08_route_feedback.ps1`
- `agents/site_auditor_v3/modules/08_route_promotion.ps1`
- `agents/site_auditor_v3/modules/07_output.ps1`
- `agents/site_auditor_v3/tests/validate_run_report.py`
- `agents/site_auditor_v3/tests/validate_self_build_loop.py`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Pipeline/module entrypoints and execution order were not changed.
- Discovery remains owned by `agents/site_auditor_v3/modules/internal_command_handlers.ps1` (`route_discovery` internal handler).
- Route feedback/promotion ownership remains in modules `08_route_feedback.ps1` and `08_route_promotion.ps1`.
- Output/report ownership remains in `07_output.ps1`.

## Risks/blockers
- Route completeness remains intentionally conservative: scope is reported as `PARTIAL` unless completeness can be proven.
- Recursive crawl currently uses HTML href extraction via regex; this is a controlled capability-pack improvement, not a full crawler engine replacement.
- No capture-consumption change was made for promoted selection (intentionally unchanged per task contract).
