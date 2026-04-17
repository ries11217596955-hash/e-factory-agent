## Summary
Normalized `Normalize-ProductCloseout` checks handling to emit deterministic string values only, and simplified the helper return payload to a plain hashtable to avoid ordered-dictionary fragility around the closeout decision payload.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent execution path: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Updated function: `Normalize-ProductCloseout`

## Risks/blockers
- No runtime execution was performed in this environment, so validation that failure now moves past the previous crash point (around line 845) must be confirmed in the next agent run.
