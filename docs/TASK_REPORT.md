## Summary
- Updated Site Auditor workflow execution to invoke the canonical agent entrypoint with an explicit absolute repository path.
- Added pre-execution trace logging to emit `RUNNING_AGENT_PATH=agents/gh_batch/site_auditor_cloud/agent.ps1` immediately before agent execution steps.
- Added post-checkout repository-root diagnostics to print `REPO_ROOT_CONTENT:` and list `agents/gh_batch/site_auditor_cloud/`.
- Enforced `actions/checkout@v4` with `fetch-depth: 0` in Site Auditor workflow files touched in scope.
- Verified there is only one `agent.ps1` in repository and removed legacy workflow invocations of `./run.ps1` / `./run_bundle.ps1` in the fixed-list workflow.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `.github/workflows/site-auditor-fetch-trace.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Canonical agent path: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Workflow execution now calls:
  - `pwsh -File agents/gh_batch/site_auditor_cloud/agent.ps1`
- Diagnostic path listing executed after checkout:
  - `ls -R agents/gh_batch/site_auditor_cloud/`

## Risks/blockers
- `DBUILD_FORENSIC_V2` confirmation requires a subsequent GitHub Actions run log; not verifiable locally in this environment.
- If stamp remains missing after this patch, likely causes match provided fail mode (different repo/branch binding or cached artifact).
