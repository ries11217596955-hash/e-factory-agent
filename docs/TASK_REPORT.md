## Summary
Implemented LINK-mode BaseUrl canonicalization so scheme-less input is converted to an absolute URL (`https://...`) before any URL parsing/fetch logic runs, and invalid URLs now fail early with `INVALID_BASE_URL`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode).
- New canonicalization gate: `Resolve-CanonicalBaseUrl` is evaluated before LINK fetch/route/screenshot target logic is executed.
- Canonical BaseUrl is propagated as single source to live fetch, route normalization, visual target selection, `RUN_REPORT.base_url`, and `LINK_SUMMARY.root` (via shared `BaseUrl` usage after canonicalization).

## Risks/blockers
- Canonical URL persistence uses trimmed input + optional `https://` prefix; it does not aggressively reformat host/path casing or force trailing slash normalization.
- Inputs that parse as absolute non-http(s) URLs are now explicitly rejected with `INVALID_BASE_URL`.
