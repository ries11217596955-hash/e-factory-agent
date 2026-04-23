## Summary
- Added deterministic DEFECT priority mapping in `SITE_AUDITOR_V2`: `BROKEN_ROUTE` and `CAPTURE_FAILURE` map to `P0`, `THIN_ROUTE` maps to `P1`, and unmapped defect types default to `P2`.
- Updated findings generation to attach `priority` to findings while preserving existing `severity` compatibility.
- Updated `priority_summary` computation to count DEFECT priorities only and keep `LIMITATION` findings excluded from `p0_count`, `p1_count`, `p2_count`, and `top_issues`.
- Enforced priority-first action routing: `top_issues`, `ACTION_SUMMARY.actions`, and `next_strongest_move` now follow strict `P0 -> P1 -> P2` order.
- Updated `operator_handoff` to explicitly declare the highest priority issue and the first action to execute.
- Updated run report schema to require findings `priority` and operator handoff priority-first fields.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report contract remains: `agents/site_auditor_v2/contracts/run_report.schema.json`.
- Output artifacts remain in `agents/site_auditor_v2/output/<run_id>/` with deterministic mirrors in `agents/site_auditor_v2/`.

## Risks/blockers
- Downstream consumers that parse findings should read `priority` as the deterministic ordering field for defect handling.
- Existing integrations that rely on `severity` remain supported, but should migrate to `priority` to match deterministic mapping rules.
- `operator_handoff` now includes `highest_priority_issue` and `what_to_do_first`; strict validators must accept these fields.
- Rollback instructions:
  1. `git revert <commit_sha>`
  2. Or restore files directly: `git checkout -- agents/site_auditor_v2/agent.ps1 agents/site_auditor_v2/contracts/run_report.schema.json docs/TASK_REPORT.md`
