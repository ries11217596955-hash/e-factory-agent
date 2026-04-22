## Summary
- Added LINK-mode diagnostic telemetry to expose fetch, extraction, and filter state in `RUN_REPORT` without changing crawler behavior.
- Added `fetch_debug` fields (`status_code`, `final_url`, `html_length`, `body_present`) and `html_snapshot` (first 1000 chars) for root-page fetch diagnostics.
- Added `raw_links_found` (pre-filter) and `internal_links` (post-filter) counters for route-discovery transparency.
- Added `filter_reason` trace when internal links resolve to zero, including explicit fetch-failure reason when root fetch fails.
- Added `link_extraction_failed=true` hard-rule signal when HTML exists but no links are extracted.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v2/agent.ps1`.
- LINK-mode route discovery diagnostics are produced in `RUN_REPORT.json` via the existing `Get-ShallowRoutes` flow.

## Risks/blockers
- Runtime validation against a live site was not executed in this environment because PowerShell runtime execution was not run during this patch; diagnostics were added via static code update only.
