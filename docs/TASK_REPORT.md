## Summary
Fixed the LINK workflow to pass the required `-BASE_URL` argument using `github.event.inputs.base_url`, and aligned the dispatch input definition to the requested `base_url` shape.

## Changed files
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml` (manual trigger via `workflow_dispatch`)
- Agent entrypoint invoked by workflow: `agents/site_auditor_v2/agent.ps1`
- Required dispatch input: `base_url`

## Risks/blockers
- No blockers identified.
- Workflow execution still depends on repository/runtime availability on GitHub-hosted runners.
