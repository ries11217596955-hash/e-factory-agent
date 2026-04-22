## Summary
Added shallow route discovery to LINK mode (depth 1): the agent now extracts `<a href>` targets from the current page, filters to same-domain `http/https` routes, de-duplicates and removes anchors, fetches up to 10 routes, and writes `ROUTES_SUMMARY.json` with status/title/html-length per route. Also updated run metadata and handoff shape in `RUN_REPORT.json`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Deterministic run report path: `agents/site_auditor_v2/RUN_REPORT.json`
- Deterministic link summary path: `agents/site_auditor_v2/LINK_SUMMARY.json`
- Deterministic routes summary path: `agents/site_auditor_v2/ROUTES_SUMMARY.json`
- Run-scoped report path: `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
- Run-scoped link summary path: `agents/site_auditor_v2/output/<run_id>/LINK_SUMMARY.json`
- Run-scoped routes summary path: `agents/site_auditor_v2/output/<run_id>/ROUTES_SUMMARY.json`

## Risks/blockers
- Network reachability and target-site behavior (timeouts, bot protection, redirects, TLS issues) can cause `LINK_FETCH_FAILED` in restricted environments.
- Route extraction is regex-based and may miss malformed links or JavaScript-generated navigation.
- Some sites may expose fewer than five eligible same-domain `http/https` links on the root page, resulting in fewer than 5 shallow routes in output.
