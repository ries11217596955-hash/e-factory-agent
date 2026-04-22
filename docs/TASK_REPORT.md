## Summary
Upgraded `site_auditor_v2` LINK mode from scaffold-only reporting to real single-page capture by fetching the `BaseUrl`, extracting minimal page signals, and writing a new `LINK_SUMMARY.json` artifact alongside updated `RUN_REPORT.json` metadata.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Deterministic run report path: `agents/site_auditor_v2/RUN_REPORT.json`
- Deterministic link summary path: `agents/site_auditor_v2/LINK_SUMMARY.json`
- Run-scoped report path: `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
- Run-scoped link summary path: `agents/site_auditor_v2/output/<run_id>/LINK_SUMMARY.json`

## Risks/blockers
- Network reachability and target-site behavior (timeouts, bot protection, redirects, TLS issues) can cause `LINK_FETCH_FAILED` in restricted environments.
- Link counting is intentionally heuristic (regex-based) and may under/over-count in malformed or script-generated markup.
