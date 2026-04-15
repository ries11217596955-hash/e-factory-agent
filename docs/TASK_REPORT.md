## Summary
- Added a `decision_summary` layer to `report.json` in `site_auditor_cloud` output generation.
- Preserved existing `report.json` fields (`overall`, `status`, `timestamp`) and appended only the new decision block.
- Implemented minimal stage classification logic: `STRUCTURE`, `PRODUCT`, `GROWTH`, otherwise `UNKNOWN`.
- Mapped summary priorities (`p0`, `p1`, `p2`) and `next_actions` directly from the existing decision layer.
- Kept pipeline/workflow/validation untouched; change is limited to report enrichment in agent output assembly.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Agent entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Report output path unchanged: `agents/gh_batch/site_auditor_cloud/reports/report.json`.
- Existing decision and audit pipelines are unchanged; only final report serialization now appends `decision_summary`.

## Risks/blockers
- Stage classification thresholds are intentionally minimal (`empty_routes >= 2` for `STRUCTURE`) and may need tuning after production feedback.
- `GROWTH` stage requires strict healthy signals (`page_quality_status=EVALUATED` plus zero blocker counters); borderline healthy sites may remain `UNKNOWN`.
