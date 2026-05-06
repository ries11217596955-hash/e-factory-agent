# TASK_REPORT

## Summary
- Updated `agents/site_auditor_v3/tests/run_and_validate.sh` to sanitize validator request inputs before running the agent wrapper.
- Added default normalization values for placeholder/missing request fields: `target_url=https://automation-kb.pages.dev/` and `scan_profile=STANDARD`.
- Preserved custom `REQUEST_PATH` support while adding a clean failure when non-bundled custom request files still contain placeholder tokens.
- Added bundled-fixture-only normalization behavior so `agents/site_auditor_v3/tests/fixtures/link.request.json` can be used safely in local validation runs.

## Changed files
- `agents/site_auditor_v3/tests/run_and_validate.sh`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Validation entrypoint remains `agents/site_auditor_v3/tests/run_and_validate.sh`.
- Agent runtime entrypoint remains `agents/site_auditor_v3/run.ps1` (invoked by the test wrapper with a resolved request path).
- Bundled placeholder fixture path is `agents/site_auditor_v3/tests/fixtures/link.request.json` and is now normalized at runtime by the wrapper when used.

## Risks/blockers
- The environment used for validation does not include `pwsh`, so full end-to-end execution cannot complete past the wrapper handoff to `run.ps1`.
- Placeholder normalization and guard behavior were validated up to wrapper-level preflight checks; full runtime assertions require a PowerShell-capable environment.
