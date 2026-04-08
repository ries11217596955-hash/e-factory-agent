## Summary
- Audited SITE_AUDITOR routing entrypoints in the fixed-list workflow and confirmed legacy CI routing was still invoking `run.ps1` directly.
- Rewired CI/post-merge (`push` to `main`) execution to use TRI-AUDIT bundle only via `run_bundle.ps1`.
- Added explicit manual execution-path selection for `workflow_dispatch` so operators can intentionally choose `BUNDLE` or `SINGLE_MODE`.
- Isolated legacy single-mode (`run.ps1`) to manual-only path and removed CI ambiguity that could force top-level ZIP resolution.
- Promoted bundle output as the primary artifact by including `audit_bundle/**` in upload output and naming artifact for bundle-first operator consumption.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- CI/post-merge auto path (`push` on `main`):
  - `.github/workflows/site-auditor-fixed-list.yml`
  - Step: `Run SITE_AUDITOR TRI-AUDIT bundle (CI/post-merge + manual bundle)`
  - Entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Manual bundle path (`workflow_dispatch` with `execution_path=BUNDLE`):
  - `.github/workflows/site-auditor-fixed-list.yml`
  - Entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Manual legacy single-mode path (`workflow_dispatch` with `execution_path=SINGLE_MODE`):
  - `.github/workflows/site-auditor-fixed-list.yml`
  - Entrypoint: `agents/gh_batch/site_auditor_cloud/run.ps1`
  - Mode source: `FORCE_MODE=${{ inputs.audit_mode }}`
- Bundle internals remain TRI-AUDIT subruns:
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` invokes `run.ps1` per subrun for `REPO`, `ZIP`, `URL`.

## Risks/blockers
- Validation in this container is limited to static workflow/script inspection because GitHub Actions runtime cannot be executed locally here.
- Bundle behavior depends on runtime inputs (ZIP payload and BASE_URL) and will still skip ZIP/URL honestly when missing by design.
