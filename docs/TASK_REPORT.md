## Summary
Fixed a PowerShell 5.1 parameter-binding failure in `Convert-RunReportValue` where an empty `HashSet[int]` passed to mandatory `VisitedReferences` caused runtime error: `Cannot bind argument to parameter 'VisitedReferences' because it is an empty collection.`

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Run report normalization function: `Convert-RunReportValue` in `agents/site_auditor_v2/agent.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Acceptance runtime (`OUTPUT: BUILD_START` through `OUTPUT: REPORT_OBJECT_READY`) was not executed in this environment, so full end-to-end confirmation and `RUN_REPORT.json` creation still require operator run validation.
- Fix is intentionally constrained to parameter binding behavior only; no route extraction, reconciliation, or report semantics were changed.
