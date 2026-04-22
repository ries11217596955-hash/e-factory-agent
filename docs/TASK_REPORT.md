## Summary
- Implemented a centralized `Get-ResponseHtml` helper with explicit extraction branches for `Invoke-WebRequest`, `Invoke-RestMethod`, and `HttpClient`.
- Enforced hard fetch assertions in root route collection: `200 + html_length == 0` now throws `FETCH_RETURNED_EMPTY_BODY`, and empty body/content sample now throws `FETCH_BODY_VALIDATION_FAILED`.
- Computed `html_length` and `body_present` immediately after fetch and before link parsing/filtering.
- Expanded mandatory fetch diagnostics to include `content_sample` (first 200 chars) and removed `final_url` from `fetch_debug` output.
- Updated report projection to pass through `status_code`, `html_length`, `body_present`, and `content_sample`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v2/agent.ps1`.
- LINK-mode route discovery diagnostics are produced in `RUN_REPORT.json` via the existing `Get-ShallowRoutes` flow.

## Risks/blockers
- Runtime validation against a live endpoint was not executed in this environment; behavior was validated by static inspection only.
