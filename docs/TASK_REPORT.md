## Summary
- Added a new TRI-AUDIT bundle orchestrator script at `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` with a top-level protective wrapper so diagnostics are still produced even if unexpected exceptions occur.
- Implemented resilient per-mode execution for `REPO`, `ZIP`, and `URL` subruns: each mode is isolated, failures are converted into structured mode-level FAIL records, and bundle execution continues.
- Preserved skip semantics for missing calibration inputs by marking ZIP as `SKIPPED` when no ZIP payload exists and URL as `SKIPPED` when `BASE_URL` is absent.
- Ensured diagnostics are always written to `audit_bundle/REPORT.txt`, `audit_bundle/master_summary.json`, and `audit_bundle/EXECUTION_LOG.txt`, including failure message and crash stage metadata.
- Kept calibration behavior non-blocking by exiting bundle with code 0 after writing diagnostics/artifacts, even when overall bundle status is FAIL.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Subrun entrypoint used by bundle: `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Always-written bundle diagnostics:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/EXECUTION_LOG.txt`
- Per-mode artifact copy targets:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/zip/`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/url/`

## Risks/blockers
- This environment does not include the full CI/runtime inputs expected by SITE_AUDITOR, so validation was limited to local script execution behavior with missing inputs.
- Existing `run.ps1`/`agent.ps1` contracts were intentionally not modified; mode-level PASS/PARTIAL classification is inferred from process exit behavior and may need future enhancement if PARTIAL must be derived from deeper report content.
