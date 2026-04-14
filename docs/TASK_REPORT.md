## Summary
- Added micro-forensics instrumentation in `Build-DecisionLayer` warnings node to replace the single `array/materialize/warnings` runtime label with five step-specific labels.
- Inserted step-level `activeOperationLabel` and `activeExpression` markers exactly before warnings-enter, warnings-enumeration, string cast, warningList add, and p1 add statements.
- Kept scope limited to the DECISION_BUILD warnings contour in `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- No repair logic, shape fixes, helper rewrites, or cross-layer/source/live changes were introduced.
- Objective is forensic pinpointing of the exact failing statement in next `FAILURE_SUMMARY.json`.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Instrumentation scope is only `Build-DecisionLayer` warnings node in DECISION_BUILD.

## Risks/blockers
- Runtime confirmation requires the next ZIP execution to verify that failure labels now surface as one of the new `warnings/stepXX/...` markers.
- If runtime still reports legacy `array/materialize/warnings`, active runtime contour may differ from edited path.
