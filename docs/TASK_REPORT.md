## Summary
- Implemented PACK R4.3 local diagnostics in `Get-ShallowRoutes` to localize the exact failing substage without adding new audit features.
- Added compact route-extraction substage trace markers via `Write-Host`:
  - `ROUTE_EXTRACTION:ROOT_FETCH_OK`
  - `ROUTE_EXTRACTION:HREF_MATCHES_READY`
  - `ROUTE_EXTRACTION:HREF_FILTER_LOOP_OK`
  - `ROUTE_EXTRACTION:ROUTE_DETAIL_LOOP_OK`
  - `ROUTE_EXTRACTION:RETURN_READY`
- Added narrow block-level exception wrappers in `Get-ShallowRoutes` with stage-local exception codes:
  - `ROUTE_EXTRACTION_ROOT_FETCH_EXCEPTION`
  - `ROUTE_EXTRACTION_HREF_LOOP_EXCEPTION`
  - `ROUTE_EXTRACTION_ROUTE_DETAIL_EXCEPTION`
  - `ROUTE_EXTRACTION_RETURN_ASSEMBLY_EXCEPTION`
- Updated `agent.ps1` failure handling to preserve localized route-extraction exception codes into failure summaries / AGENT failure artifacts, instead of collapsing immediately to generic `ROUTE_EXTRACTION_FAILED`.
- Updated runtime failure classification handling for route-extraction internal runtime errors (including "Argument types do not match") so they are treated as agent/runtime defects (`AGENT_DEFECT`) rather than object defects.
- ROUTE_EXTRACTION_LOCALIZER_ACTIVE = YES

## Changed files
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - Added substage marker output lines and block-level try/catch throws for localization.
- `agents/site_auditor_v2/agent.ps1`
  - Added localized error-code extraction and effective failure-class mapping for route runtime exceptions.
  - Preserved localized route exception code in failure summary path.
- `docs/TASK_REPORT.md`
  - Rewritten for this task with diagnostics/classification details.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`
- Localized route-extraction logic path: `agents/site_auditor_v2/modules/stage_link_fetch.ps1`

## Risks/blockers
- `pwsh` runtime is not available in this container, so end-to-end PowerShell execution validation could not be run locally.
- Added marker lines are intentionally compact and only diagnostics-oriented; they can increase action-log verbosity during failures.

## Rollback instructions
1. Revert commit for this pack:
   - `git revert <commit_sha>`
2. Or discard local patch before merge:
   - `git checkout -- agents/site_auditor_v2/modules/stage_link_fetch.ps1 agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
3. Re-run existing LINK-mode workflow to confirm previous behavior baseline.
