## Summary
- Fixed the live-layer runtime type mismatch by normalizing visual manifest route data before evaluation, eliminating hard casts against inconsistent JSON shapes.
- Added stage-specific diagnostics (`CAPTURE`, `LOAD_VISUAL_MANIFEST`, `ROUTE_NORMALIZATION`, `ROUTE_MERGE`, `PAGE_QUALITY_BUILD`) so failures are attributable to the exact live audit phase.
- Made page-quality reporting explicit with `page_quality_status` values (`EVALUATED`, `PARTIAL`, `NOT_EVALUATED`) and ensured partial/failure states are surfaced in warnings and decision output.
- Prevented misleading clean zero rollups when live evaluation is not completed by reporting rollups as unavailable in `REPORT.txt` / executive summary for `NOT_EVALUATED` states.
- Preserved partial visual value by retaining normalized route details in live-layer fallback responses when downstream live evaluation fails.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary cloud agent entrypoint remains: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Output contract remains unchanged:
  - `outbox/REPORT.txt`
  - `reports/audit_result.json`
  - `reports/run_manifest.json`
  - `outbox/DONE.ok` / `outbox/DONE.fail`

## Risks/blockers
- Runtime verification of the end-to-end live capture path was limited in this environment because PowerShell (`pwsh`) is unavailable.
- Stage-level diagnostics were added to reduce troubleshooting risk in CI and to make follow-up validation actionable.
