## Summary
Added a deterministic `operator_feed` block to the LINK-mode `RUN_REPORT.json` report layer, derived from current run state (`capture_report`, `evidence_reconciliation`, `selected_routes`, `run_budget`, `findings`) and scoped to system-level operator guidance only.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode only).
- RUN_REPORT contract path remains `agents/site_auditor_v2/contracts/run_report.schema.json`.
- `RUN_REPORT.json` now includes `operator_feed` with deterministic fields: `system_state`, `primary_constraint`, `truth_confidence`, `what_is_reliable`, `what_is_not_reliable`, `next_system_move`, `why_this_move`, `do_not_do_yet`.

## Risks/blockers
- `operator_feed` intentionally excludes website/content interpretation and only reflects system state from existing report truth sources.
- If required source state is unavailable, `operator_feed` remains in its empty default form to avoid fabricated guidance.
