## Summary
Created a minimal manual GitHub Actions workflow for `site_auditor_v2` LINK-only execution with a required `base_url` input and output-path logging.

## Changed files
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml` (manual trigger via `workflow_dispatch`)
- Agent entrypoint invoked by workflow: `agents/site_auditor_v2/agent.ps1`
- Expected output paths logged:
  - `agents/site_auditor_v2/RUN_REPORT.json`
  - `agents/site_auditor_v2/failure_summary.json` (if present)

## Risks/blockers
- Assumes `pwsh` is available on `ubuntu-latest` (standard on GitHub-hosted Ubuntu runners).
- Assumes `agents/site_auditor_v2/agent.ps1` handles LINK mode and exits with code `0`/`1` as required.
