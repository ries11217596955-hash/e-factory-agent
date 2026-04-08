## Summary
- Fixed TRI-AUDIT bundle guardrails in `run_bundle.ps1` by validating script syntax/tokens before mode execution starts.
- Added explicit preflight logging line: `Validating PowerShell syntax...` so bundle logs show syntax validation before subruns.
- Added AST/token-based validation to detect parser issues and standalone invalid logical tokens (`and`/`or`) in the script source.
- Verified no raw ` and ` / ` or ` operator-style tokens remain in `run_bundle.ps1`.
- Kept the existing execution flow intact so REPO/ZIP/URL subruns continue under the same deterministic orchestration model.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- TRI-AUDIT bundle entrypoint:
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Bundle artifact paths:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/EXECUTION_LOG.txt`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`

## Risks/blockers
- `pwsh` runtime execution is not validated in this environment; only static/token checks were run from shell tooling.
- If external edits later introduce invalid tokens, the new validator logs the condition but intentionally does not terminate execution.
