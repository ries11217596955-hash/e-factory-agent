## Summary
Fixed `SITE_AUDITOR` artifact path resolution so runtime output paths match GitHub Actions artifact upload expectations. `agent.ps1` now resolves a workspace-aware base path from `$env:GITHUB_WORKSPACE` when running in Actions, falls back to `$PSScriptRoot` for local execution, rebuilds `outbox/`, `reports/`, and `runtime/` from that base, and logs the resolved output base.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Downstream outputs (now rooted at `"$GITHUB_WORKSPACE/agents/gh_batch/site_auditor_cloud"` in GitHub Actions, otherwise script root):
  - `agents/gh_batch/site_auditor_cloud/reports/audit_result.json`
  - `agents/gh_batch/site_auditor_cloud/outbox/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.ok`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.fail`
  - existing optional reports from normal flow remain unchanged (`HOW_TO_FIX.json`, `00_PRIORITY_ACTIONS.txt`, `01_TOP_ISSUES.txt`, `11A_EXECUTIVE_SUMMARY.txt`, `run_manifest.json`).

## Risks/blockers
- This change assumes GitHub Actions checks out the repository at `$GITHUB_WORKSPACE` (standard behavior); custom checkout paths could still require workflow-side alignment.
- End-to-end artifact upload validation requires a GitHub Actions run; local validation can only verify path selection logic and script syntax.
