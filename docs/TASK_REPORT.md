## Summary
- Hardened LINK-mode report truth fields in `SITE_AUDITOR_V2` so critical handoff fields are always populated and bounded to sampled evidence.
- Added deterministic `next_strongest_move` derivation that never returns null and maps to the highest-priority finding class when findings exist.
- Added non-null `operator_handoff.must_read_first` with fixed value `["RUN_REPORT.json"]` to enforce deterministic operator read entrypoint.
- Replaced overclaim-prone handoff reasoning with sampled-scope bounded wording, including the exact required message for single `ROUTE_OVERFLOW_ONLY` finding runs.
- Kept findings generation logic, route logic, visual/capture logic, and ACTION summary generation behavior unchanged.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- LINK output contract remains under: `agents/site_auditor_v2/output/<run_id>/`.
- Deterministic mirror artifacts remain under: `agents/site_auditor_v2/` (`RUN_REPORT.json`, `ACTION_SUMMARY.json`, and related summaries).

## Risks/blockers
- This patch intentionally hardens reporting/handoff truth only; no remediation of underlying site issues is introduced.
- `next_strongest_move` mapping depends on finding class labels staying stable (`CAPTURE_FAILURE`, `BROKEN_ROUTE`, `THIN_ROUTE`, `ROUTE_OVERFLOW_ONLY`); unknown classes safely fall back to a generic deterministic action token.
- `ROUTE_OVERFLOW_ONLY` remains a non-defect sampled-coverage limitation and must not be interpreted as a confirmed page defect.

## Why nulls are forbidden
- `next_strongest_move` and `must_read_first` are operator-critical direction fields; null values break deterministic handoff and can cause ambiguous or unsafe downstream decisions.
- Enforcing non-null values ensures each run has a minimum viable, machine-readable operator next step and read order anchor.

## next_strongest_move derivation
- If `findings_count == 0`: set `next_strongest_move = "expand_route_sample_within_budget"`.
- If `findings_count > 0`: select the highest-priority finding class (severity order `P0 -> P1 -> P2`, then `finding_id`) and map:
  - `ROUTE_OVERFLOW_ONLY` -> `increase_route_sample_or_adjust_budget`
  - `CAPTURE_FAILURE` -> `restore_capture_integrity_and_rerun_link_mode`
  - `BROKEN_ROUTE` -> `repair_broken_routes_and_rerun_link_mode`
  - `THIN_ROUTE` -> `expand_route_content_and_rerun_link_mode`
  - default -> `resolve_highest_priority_finding_from_run_report`

## Rollback instructions
1. Revert the commit produced by this task:
   - `git revert <commit_sha>`
2. Or restore file state directly:
   - `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
3. Re-run LINK mode to regenerate `RUN_REPORT.json` and validate previous behavior restoration.
