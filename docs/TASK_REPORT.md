## Summary
Implemented a strict LINK-mode run budget control layer with hard cap enforcement (`max_routes = 5`) and explicit route-selection traceability. Selected routes now include `selection_reason`, the run report now includes a `run_budget` block (including overflow accounting and excluded-route detail), and mismatch/overflow behavior now fails with `run_budget_violation` semantics.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Run-budget selection path: `Get-VisualTargets` now returns `selected_routes`, `overflow_routes`, and `selection_strategy`.
- RUN_REPORT contract path: `agents/site_auditor_v2/contracts/run_report.schema.json` now includes `selected_routes[].selection_reason` and `run_budget`.
- LINK-mode enforcement path now explicitly hard-fails out-of-budget page-set mismatches as `run_budget_violation`.

## Risks/blockers
- Validation performed in-repo (static checks + schema parse only); no live external LINK crawl was executed in this environment.
- Existing downstream consumers that assumed the old `COUNTER_INCONSISTENCY` reason code must now handle `run_budget_violation`.
