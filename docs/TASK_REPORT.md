## Summary
- Added `audit_confidence` to SITE_AUDITOR_V2 `RUN_REPORT` output with enum values `HIGH`, `MEDIUM`, and `LOW`.
- Implemented confidence mapping that keeps findings logic unchanged and evaluates confidence from coverage and limitation signals:
  - `LOW` when sampled routes are below run budget (`routes_checked < max_routes`) or when limitation findings exist (for example `ROUTE_OVERFLOW_ONLY`).
  - `HIGH` when confidence is not low, no defects are detected, and near/full coverage is present (`routes_checked / max_routes >= 0.9`).
  - `MEDIUM` for remaining cases (moderate coverage without major limitations).
- Updated wording gates so low-confidence clean outcomes never claim the site is clean:
  - `operator_handoff.exact_reason` now emits `No issues found in sampled scope. Audit coverage is limited.` when confidence is `LOW`.
  - `operator_handoff.exact_reason` can emit `No defects detected.` only when confidence is `HIGH` and no defects are present.
- Updated clean-run `ACTION_SUMMARY` guidance via `executive_answer.strongest_next_move` so low-confidence clean runs recommend increasing coverage instead of asserting cleanliness.
- Updated run report schema contract to require and validate `audit_confidence`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report contract remains: `agents/site_auditor_v2/contracts/run_report.schema.json`.
- Report artifacts remain under `agents/site_auditor_v2/output/<run_id>/` with deterministic mirrors in `agents/site_auditor_v2/`.

## Risks/blockers
- Downstream consumers that validate `RUN_REPORT.json` must adopt the schema update requiring `audit_confidence`.
- Confidence uses route-budget coverage as a deterministic proxy (`selected_routes` vs `max_routes`), which can conservatively classify naturally small sites as lower confidence when route count stays under budget.
- Rollback instructions:
  1. `git revert <commit_sha>`
  2. Or restore files directly: `git checkout -- agents/site_auditor_v2/agent.ps1 agents/site_auditor_v2/contracts/run_report.schema.json docs/TASK_REPORT.md`
