## Summary
Implemented basic per-route page classification for LINK mode with deterministic rules (`broken` when status is not 200, `thin` when HTML length is below 1500, otherwise `ok`). Updated `ROUTES_SUMMARY.json` route entries to include `classification`, added a new `AUDIT_SUMMARY.json` artifact with aggregate counts, and updated `RUN_REPORT` metadata plus handoff `next_task_shape`.

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
- Deterministic audit summary path: `agents/site_auditor_v2/AUDIT_SUMMARY.json`
- Run-scoped report path: `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
- Run-scoped link summary path: `agents/site_auditor_v2/output/<run_id>/LINK_SUMMARY.json`
- Run-scoped routes summary path: `agents/site_auditor_v2/output/<run_id>/ROUTES_SUMMARY.json`
- Run-scoped audit summary path: `agents/site_auditor_v2/output/<run_id>/AUDIT_SUMMARY.json`

## Risks/blockers
- Network reachability and target-site behavior (timeouts, bot protection, redirects, TLS issues) can still cause `LINK_FETCH_FAILED`.
- Classification is intentionally threshold-based and may over/under-classify pages with atypical markup density.
