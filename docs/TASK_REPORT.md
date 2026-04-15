## Summary
- Introduced `Finalize-Report` as the single, guaranteed writer for `reports/report.json`.
- Moved final `reportObject` handling to script scope so report data survives any upstream branch.
- Removed mid-flow `report.json` write from `Write-OperatorOutputs` to enforce single write point.
- Added unconditional `Finalize-Report -ReportObject $reportObject -BasePath $base` invocation after `finally`.
- Preserved existing workflow, validation, and decision logic while making report persistence fail-safe.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Final report write path: `Join-Path $BasePath 'reports/report.json'` inside `Finalize-Report`.
- Single write contract: only `Finalize-Report` writes `report.json`, invoked once at script end.

## Risks/blockers
- No workflow, validation criteria, or decision-building behavior was changed.
- Local CI workflow was not executed in this environment; GitHub Actions should verify `Upload reports` and `Validate agent result`.
