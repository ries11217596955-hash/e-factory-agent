## Summary
- Rewired `.github/workflows/site-auditor-fixed-list.yml` to execute the TRI-AUDIT bundle orchestrator with `pwsh ./run_bundle.ps1` instead of legacy `run.ps1`.
- Expanded target repo checkout condition so `target_repo` is fetched for both push-to-main and manual REPO-triggered runs.
- Removed legacy push-only `FORCE_MODE=ZIP` workflow wiring so mode decisions are handled by `run_bundle.ps1`.
- Passed bundle-specific environment inputs in workflow (`TARGET_REPO_PATH`, `EXPLICIT_BASE_URL`, `DEFAULT_BASE_URL`) to support manual override with default fallback behavior.
- Updated artifact upload paths so bundle outputs under `agents/gh_batch/site_auditor_cloud/audit_bundle/**` are always included as primary run artifacts (while keeping outbox/reports uploads).

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow trigger entrypoints retained:
  - `workflow_dispatch`
  - `push` on `main` (path-filtered)
- Workflow runtime entrypoint now used:
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Workflow checkout/inputs and artifact paths:
  - Target repo checkout path: `${{ github.workspace }}/target_repo`
  - Bundle env: `TARGET_REPO_PATH`, `EXPLICIT_BASE_URL`, `DEFAULT_BASE_URL`
  - Uploaded artifact paths include:
    - `agents/gh_batch/site_auditor_cloud/audit_bundle/**`
    - `agents/gh_batch/site_auditor_cloud/outbox/**`
    - `agents/gh_batch/site_auditor_cloud/reports/**`

## Risks/blockers
- CI validation of push-to-main behavior cannot be executed locally from this environment; verification of generated `audit_bundle/*` artifacts depends on the next GitHub Actions run after merge.
- Workflow still depends on `secrets.GH_BATCH_PAT` for target repository checkout; missing/invalid secret would block target repo binding during CI runs.
