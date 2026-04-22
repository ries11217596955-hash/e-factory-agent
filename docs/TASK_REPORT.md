## Summary
- Added a single entry canonicalization gate in LINK mode that transforms input `BaseUrl` into a mandatory canonical absolute URL before downstream execution.
- Canonicalization now applies trim, scheme injection (`https://` when missing), absolute http/https validation, and trailing-slash normalization (except root).
- Added `input_canonicalization` trace in `RUN_REPORT` with original input, canonical value, and status.
- Updated failure handling to stop early with `INVALID_BASE_URL` when canonicalization fails (no fetch path entered).

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode).
- Entry lock is enforced at startup: canonicalization is resolved once and propagated to fetch, route discovery/normalization, screenshot targeting, `RUN_REPORT`, and `LINK_SUMMARY`.

## Risks/blockers
- Validation was limited to static/structural checks in this environment because PowerShell (`pwsh`) is unavailable, so full runtime verification could not be executed here.
