## Summary
Added operator-readable `ACTION_REPORT.txt` generation from `problem_targets`, added summary header counts, and updated `RUN_REPORT` artifact/link lists to include `ACTION_REPORT.txt`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- New artifact output: `ACTION_REPORT.txt`
- Existing artifact output retained: `ACTION_SUMMARY.json`
- Updated run report outputs: `RUN_REPORT.json -> produced_artifacts`, `RUN_REPORT.json -> linked_artifacts`

## Risks/blockers
- None.
