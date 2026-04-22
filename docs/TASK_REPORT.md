## Summary
Added a GitHub Actions artifact upload step to publish deterministic site_auditor_v2 run outputs from the LINK workflow so run outputs are downloadable from each workflow execution.

## Changed files
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml`
- Uploaded artifact name: `site-auditor-v2-link-output`
- Uploaded RUN report path: `agents/site_auditor_v2/RUN_REPORT.json`
- Uploaded failure summary path: `agents/site_auditor_v2/failure_summary.json`

## Risks/blockers
- No blockers identified.
- `failure_summary.json` is optional on PASS runs; upload behavior is configured to avoid workflow failure when that file is absent.
