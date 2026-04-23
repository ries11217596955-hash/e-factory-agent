## Summary
- Implemented a decision consolidation layer in `RUN_REPORT` with a new `decision_summary` block (`primary_issue`, `issue_type`, `recommended_action`, `reasoning`) driven by existing findings and priority order.
- Hardened `next_strongest_move` so it is always present, expressed as a single human-action instruction, and aligned with ownership mode, confidence, and priority.
- Reworked final `ACTION_SUMMARY.json` generation to produce at most 3 concrete actions with the exact shape `{ action, why, priority }`, with the first action anchored to the highest-priority issue.
- Added deterministic generation of `HUMAN_REPORT.md` (plus fallback generation) with non-technical sections: quick verdict, checked scope, key findings, next move, impact rationale, and limitations.
- Updated operator handoff to reduce overclaiming and include explicit `issue_type`, `audit_confidence`, and `scope_limited` state for clearer human review boundaries.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/site_auditor_v2/agent.ps1`.
- Main outputs remain in `agents/site_auditor_v2/output/<run_id>/` with deterministic mirrors in `agents/site_auditor_v2/`.
- Decision/report outputs now include `RUN_REPORT.json` (`decision_summary`, hardened `next_strongest_move`), `ACTION_SUMMARY.json` (priority-aligned top actions), and `HUMAN_REPORT.md`.

## Risks/blockers
- `ACTION_SUMMARY.json` action objects were intentionally simplified to `{ action, why, priority }`; downstream readers expecting older fields (`finding_id`, `route`, `evidence_refs`) may need to adapt.
- No schema files were changed in this task scope, so strict external validators that enforce older shapes could reject updated payloads until contracts are updated in a future allowed task.
- `next_strongest_move` now uses plain-language instructions rather than identifier-like tokens; integrations expecting machine-style enums may need mapping.
- Rollback steps:
  1. `git revert <commit_sha>`
  2. Or restore files directly: `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
