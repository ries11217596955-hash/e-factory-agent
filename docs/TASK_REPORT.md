## Summary
Fixed the ROUTES_SUMMARY contract mismatch that was causing REPORT_LAYER to fail with `ROUTES_SUMMARY_INVALID: missing routes property` despite successful RECON/OUTPUT stages. The producer path in `agent.ps1` now normalizes the route extraction result into a contract-safe object and always writes top-level `routes` (array), `route_count` (number), `status`, and `sampled_count` (when `selected_count` is not already present), while preserving all existing fields.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator: `agents/site_auditor_v2/agent.ps1`
- ROUTES_SUMMARY producer path: LINK flow route extraction block before writing `ROUTES_SUMMARY.json`
- Report-layer consumer trigger impacted by this contract: `Resolve-MinimalDecision` invocation from `agent.ps1` (uses normalized `$routesSummary`)

## Risks/blockers
- Could not execute the full LINK workflow locally in this environment, so GitHub Actions confirmation is still required for final green run verification.
- Contract fix is intentionally minimal and scoped to ROUTES_SUMMARY shape normalization only (no workflow/capture/artifact-pack changes).
