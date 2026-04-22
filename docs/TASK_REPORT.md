## Summary
Implemented a bounded hotfix in `site_auditor_v2` so every FAIL state in `RUN_REPORT` references `failure_summary.json`, and ensured counter mismatch FAIL flow writes a compliant `failure_summary.json` artifact with required contract fields.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- FAIL contract reference path: `report.failure_or_limit_report` now enforced to `kind=FAILURE` + `failure_summary=failure_summary.json` before FAIL exit.
- Counter mismatch FAIL path: `counter_inconsistency` path now explicitly references `failure_summary.json`.
- FAIL artifact write path: `failure_summary.json` write now includes required minimum fields (`error_code`, `error_message`, `fail_class`, `notes`, `must_read_files`) and includes last-resort fallback write.

## Risks/blockers
- Validation in this environment was static (script inspection/lint-level) and did not execute a live external LINK run.
- Last-resort write uses direct JSON serialization as a fallback only when the primary writer fails.
