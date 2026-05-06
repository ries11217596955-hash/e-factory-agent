## Summary
- Repaired fail-path RUN_REPORT contract in `agents/site_auditor_v3/modules/07_output.ps1` by adding a deterministic fallback `decision_action` object for pre-decision pipeline failures.
- Added `$safeDecisionAction` and `$safeNextStep` resolution logic so both root fields are always populated with objects, preventing null contract output on fail paths.
- Preserved normal-path precedence order and did not modify module ownership, validators, or upstream input/decision modules.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Orchestrator entrypoint unchanged: `agents/site_auditor_v3/run.ps1`.
- RUN_REPORT writer unchanged: `agents/site_auditor_v3/modules/07_output.ps1`.
- RUN_REPORT output path unchanged: `agents/site_auditor_v3/runs/<run_id>/RUN_REPORT.json`.

## Risks/blockers
- `pwsh` is not available in this execution environment, so PowerShell parse/runtime validation scenarios could not be executed here.
- Validator no-Traceback checks for invalid `target_url` and invalid `scan_profile` require `pwsh` runtime to generate fresh run artifacts.
