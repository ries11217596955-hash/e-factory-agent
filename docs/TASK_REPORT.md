## Summary
- Fixed ROUTE_EXTRACTION internal link handling in `stage_link_fetch.ps1` by replacing safe URI resolution with deterministic absolute URL construction for only `/<relative>` and `http*` href values.
- Enforced same-host filtering against the root host before accepting links as internal.
- Switched route normalization in shallow route collection to use `AbsolutePath` directly with explicit fallback to `/`.
- Preserved existing pipeline flow and route sampling behavior while ensuring accepted links increment `internal_links` and populate `routes`.

## Changed files
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - Updated `Get-HrefResolutionResult` with deterministic href-to-absolute logic and host equality filter.
  - Updated `Get-ShallowRoutes` loop to derive route keys from `AbsolutePath` and append internal routes directly.
- `docs/TASK_REPORT.md`
  - Updated task report for this logic-fix task.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Modified extraction module path: `agents/site_auditor_v2/modules/stage_link_fetch.ps1`.

## Risks/blockers
- `pwsh` is unavailable in this container, so PowerShell contract test execution could not be completed locally.
- Deterministic acceptance intentionally ignores non-leading-slash relative hrefs (e.g., `about`, `./about`) per requested constraints.
