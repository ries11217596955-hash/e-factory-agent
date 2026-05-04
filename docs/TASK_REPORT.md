## Summary
- Updated RUN_REPORT object construction in `agents/site_auditor_v3/modules/07_output.ps1` so required decision/diagnostic fields are emitted first-class at the root report level.
- Ensured the required top-level keys are directly present on the final `$report` object: `run_id`, `verdict`, `score`, `limitations`, `finding_counts`, `evidence_quality`, `decision_reason`, `decision`, `self_build`, `self_diagnostic`.
- Kept writer ownership in module 07 and left modules 01–06, guards, and validators untouched.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Orchestrator entrypoint unchanged: `agents/site_auditor_v3/run.ps1`.
- RUN_REPORT writer unchanged: `agents/site_auditor_v3/modules/07_output.ps1`.
- Report output path unchanged: `agents/site_auditor_v3/runs/<run_id>/RUN_REPORT.json`.

## Risks/blockers
- None identified in code changes.
- Test outcomes depend on local availability of required runtime tools (`bash`, `pwsh`, test fixtures).
