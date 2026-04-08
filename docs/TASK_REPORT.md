## Summary
- Fixed unsafe PowerShell interpolation in live-stage failure messaging by bracing `$liveStage` where it is immediately followed by a colon, preventing parse/runtime interpolation issues while preserving existing message contract.
- Preserved the current live-layer hardening behavior and output schema; only interpolation safety was adjusted in the live audit failure path.
- Updated the `site-auditor-fixed-list` workflow to auto-run on pushes to `main`.
- Scoped push-triggered workflow execution to SITE_AUDITOR code and its workflow file only.
- Kept manual `workflow_dispatch` execution behavior intact.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Workflow entrypoint remains: `.github/workflows/site-auditor-fixed-list.yml`.
- Output contract remains unchanged:
  - `outbox/REPORT.txt`
  - `reports/audit_result.json`
  - `reports/run_manifest.json`
  - `outbox/DONE.ok` / `outbox/DONE.fail`

## Risks/blockers
- End-to-end runtime validation of `pwsh` execution was not performed in this environment; validation here is static/diff-based.
- Workflow behavior change depends on GitHub Actions event context (push to `main` with matching path filters) and should be confirmed in CI after merge.
