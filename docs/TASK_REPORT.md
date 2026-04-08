## Summary
- Refactored `run_bundle.ps1` into a strict 3-stage runtime (`EXECUTION -> ASSEMBLY -> WRITING`) so orchestration, status computation, and file output are separated.
- Kept REPO as the only active subrun and forced ZIP/URL to deterministic `SKIPPED_BY_STAGE_ACTIVATION` mode results.
- Simplified diagnostics output so writer stage only serializes pre-assembled objects and does not execute bundle business logic.
- Added a minimal emergency fallback writer that creates a plain text report and execution log if diagnostics writing fails.
- Aligned final exit-code behavior to a single end-of-run decision from assembled status (`0` only when REPO produced usable evidence: `PASS` or `PARTIAL`).

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle runtime entrypoint:
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Subrun entrypoint used by REPO stage execution:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
- Bundle artifacts written by stage 3:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/EXECUTION_LOG.txt`

## Risks/blockers
- Runtime behavior still depends on `run.ps1` for REPO execution outcomes; this task intentionally does not modify REPO internals.
- If the environment cannot execute PowerShell (`pwsh` unavailable), end-to-end local runtime validation is limited and should be verified in CI or a PowerShell-capable runner.
