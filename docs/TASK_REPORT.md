## Summary
- Rewired the SITE_AUDITOR workflow so `push` to `main` executes the bundle entrypoint (`run_bundle.ps1`) and `workflow_dispatch` remains available for single-mode runs (`run.ps1`).
- Added REPO-first checkout behavior for both auto-runs and manual REPO runs, with explicit target-checkout diagnostics exported to runtime env for operator visibility.
- Changed artifact publishing to one primary bundle artifact (`site-auditor-bundle`) sourced from `audit_bundle/**`, so operators can use one artifact for end-to-end diagnosis.
- Hardened bundle mode isolation by resetting `outbox/` and `reports/` before each subrun, preventing cross-mode artifact bleed in per-mode folders.
- Updated bundle status semantics so failed mode invocations with usable evidence are reported as `PARTIAL` (instead of hard `FAIL`), while no-evidence failures stay `FAIL` and missing ZIP/URL inputs remain `SKIPPED`.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Auto-run bundle entrypoint (push to `main`): `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Manual single-mode entrypoint (`workflow_dispatch`): `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Primary artifact bundle path: `agents/gh_batch/site_auditor_cloud/audit_bundle/**`.
- Required bundle diagnostics files:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/EXECUTION_LOG.txt`
- Per-mode output folders under bundle:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/zip/`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/url/`

## Risks/blockers
- Local container does not include `pwsh`, so PowerShell runtime validation was not executable here; workflow/runtime behavior is validated by static edits and YAML parse only.
- The workflow uses `continue-on-error` for target repo checkout to preserve diagnostics-first behavior; if checkout fails, REPO mode will still run and report explicit failure rather than silently passing.
- URL live-audit quality remains intentionally non-gold in this macro pass; this change targets honest mode status + operator-usable bundling baseline.
