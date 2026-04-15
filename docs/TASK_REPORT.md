## Summary
- Restored strict `report.json` write contract in `site_auditor_cloud` finalization block.
- Ensured `reportObject` is created before conditional `decision_summary` attachment.
- Added null-guard before serialization: throws if `reportObject` is null before write.
- Forced final write target to `Join-Path $base 'reports\report.json'`.
- Increased final report serialization depth to `ConvertTo-Json -Depth 10` for decision payload safety.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Final report write path: `Join-Path $base 'reports\report.json'`.
- Final report writer contract: `$reportObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportOutputPath -Encoding utf8`.

## Risks/blockers
- No workflow/pipeline/validation/decision-helper logic was changed.
- Validation run was not executed in this environment; CI should confirm end-to-end report contract behavior.
