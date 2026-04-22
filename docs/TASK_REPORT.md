## Summary
Enforced reconciliation as the strict final gate for visual capture truth in LINK mode. `RUN_REPORT.capture_report.status` is now always set directly from reconciliation status, non-PASS capture now hard-locks decisions via `decision_allowed = false`, and reconciliation enforcement is explicitly logged.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Visual capture runtime entrypoint: `agents/site_auditor_v2/tools/capture_visuals.mjs`
- Deterministic outputs retained:
  - `agents/site_auditor_v2/RUN_REPORT.json`
  - `agents/site_auditor_v2/visual_manifest.json`
  - `agents/site_auditor_v2/screenshots/*.png`
- Run-scoped outputs retained:
  - `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
  - `agents/site_auditor_v2/output/<run_id>/visual_manifest.json`
  - `agents/site_auditor_v2/output/<run_id>/screenshots/*.png`

## Risks/blockers
- Reconciliation now compares manifest pages, filesystem screenshots, and RUN_REPORT counters; any counter drift introduces explicit reconciliation issues and can force non-PASS outcomes.
- If reconciliation returns an unsupported status or throws, execution is hard-failed with decision lock and no PASS fallback.
