## Summary
Applied a bounded hotfix for `Get-VisualTargets` in LINK mode to remove the `ContainsKey` runtime crash against ordered route classification results. Replaced invalid dictionary-method access with PowerShell-safe property checks, and added a fail-safe classification wrapper that defaults malformed/unsafe metadata to `CONTENT` without terminating the run.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent runtime entrypoint: `agents/site_auditor_v2/agent.ps1`
- Route prioritization path: `Get-VisualTargets` (ROOT/DECISION tier 1, CONTENT tier 2, LOW_VALUE exclusion, hard excludes, max-routes cap)
- Route classification path: `Get-RouteTypeAndPriority` + `Get-SafeRouteClassification` fail-safe access wrapper
- RUN_REPORT propagation path: `selected_routes` remains sourced from visual target selection output

## Risks/blockers
- Validation in this environment is limited to static/script-level checks; a full external LINK-mode run artifact was not executed here.
- Fail-safe intentionally coerces malformed classification metadata to `CONTENT` to prevent run-ending exceptions, which may reduce specificity for malformed items while preserving pipeline continuity.
