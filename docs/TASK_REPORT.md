## Summary
- Patched `agents/site_auditor_v3/modules/07_output.ps1` so `RUN_REPORT.json` now emits the required validator/visibility contract fields at the top level while preserving existing operator-facing sections.
- Added derived top-level fields from current pipeline state and decision output: `run_id`, `verdict`, `score`, `limitations`, `finding_counts`, `evidence_quality`, `decision_reason`, `decision`, `self_build`, and `self_diagnostic`.
- Kept nested `audit_result`, `evidence_summary`, `agent_capability_state`, `pipeline_status`, and readable guidance structure intact.
- Implemented diagnostic fallback values when decision output is missing, without fabricating PASS.
- Did not modify modules 01–06, validator logic, guard scripts, or orchestrator behavior.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains orchestrator-only: `agents/site_auditor_v3/run.ps1`.
- Writer remains module 07 only: `agents/site_auditor_v3/modules/07_output.ps1`.
- Output contract target remains: `agents/site_auditor_v3/runs/<run_id>/RUN_REPORT.json`.

## Risks/blockers
- Local environment blocker: `pwsh` is not installed, so `./agents/site_auditor_v3/tests/run_suite.sh` cannot execute end-to-end in this container.
- Because suite execution failed before run generation, contract assertions against a newly generated `RUN_REPORT.json` could not be completed locally.
