## Summary
Applied a bounded compatibility rollback in `Build-DecisionLayer` (`contradiction_summary_build`) to restore fail-parity behavior by removing the active runtime `Build-ContradictionLayer` invocation from the decision path. Replaced it with the temporary compatibility `contradictionSummary` shape requested by the task. The extracted contradiction module and imports were left intact.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Decision runtime patch scope: `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1` (`contradiction_summary_build` only)
- Extracted contradiction module retained and untouched: `agents/gh_batch/site_auditor_cloud/modules/decision_contradictions.ps1`

## Risks/blockers
- Runtime parity execution could not be validated in-container because `pwsh` is not available in this environment.
- Requested runtime values (`final_status`, `failed_step`, `final_stage`, `last_success_stage`) were therefore not directly observed from execution output.
