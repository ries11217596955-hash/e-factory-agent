## Summary
Added explicit `problem_targets` generation from `ROUTES_SUMMARY` in LINK mode: all `broken` routes plus the top 3 `thin` routes with the lowest `html_length`. Updated `RUN_REPORT` to include `problem_targets` and replaced operator handoff instructions with targeted page-level inspection steps, including `what_to_inspect_next`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- New run report block: `RUN_REPORT.json -> problem_targets`
- Updated operator handoff block: `RUN_REPORT.json -> operator_handoff`
- Source for target selection: `ROUTES_SUMMARY.json -> routes[*]`

## Risks/blockers
- If fewer than 3 thin routes are present, `problem_targets` will include fewer thin entries.
- Route sampling remains shallow (`MaxRoutes = 10`), so target coverage is limited to sampled routes.
