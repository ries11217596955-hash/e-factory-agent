## Summary
- Reworked the decision/output block in `site_auditor_cloud` to enforce the requested hard `CORE PROBLEM` rule based on `content_empty_routes` and `visual_health_score`.
- Replaced P0 generation with the requested filtered rule set (no hard cap), plus de-duplication and empty-line filtering.
- Split follow-up actions into `DO NEXT NOW` and `DO NEXT AFTER` with deterministic, actionable items and anti-noise filtering.
- Replaced executive summary format in `outbox/11A_EXECUTIVE_SUMMARY.txt` with the strict stage/core/P0/now/after template.
- Added operator outbox artifacts `outbox/00_PRIORITY_ACTIONS.txt` and `outbox/01_TOP_ISSUES.txt` from the same decision layer.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Decision input unchanged: `reports/audit_result.json`.
- Operator outputs now include:
  - `outbox/00_PRIORITY_ACTIONS.txt`
  - `outbox/01_TOP_ISSUES.txt`
  - `outbox/11A_EXECUTIVE_SUMMARY.txt`

## Risks/blockers
- When both `content_empty_routes` and low `visual_health_score` conditions are false, `P0` can be empty by design (per requested rules).
- This change only updates decision/operator text outputs; it does not alter audit collection or scoring behavior.
