## Summary
- Fixed `New-ActionSummaryFromDecision` to lock ACTION_SUMMARY status to audit truth so `CLEAN` is impossible when broken routes are present or when run status is `FAIL`.
- Added explicit audit-truth inputs (`AuditBrokenRouteCount`, `RunStatus`, `RunStatusLabel`) and merged them into `effectiveDefectCount`/status derivation.
- Enforced broken-route-first remediation when broken route truth is positive, so first action always targets route repair.
- Added `status_label` and `broken_route_count` fields in ACTION_SUMMARY to keep explicit alignment with failure/audit artifacts.
- Strengthened consistency lock guards to fail fast on contradictions between action summary, defect truth counts, and fail status.

## Changed files
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Action summary generation remains in `New-ActionSummaryFromDecision` within `agents/site_auditor_v2/modules/report_layer.ps1`.
- Report consistency enforcement remains in `Test-ReportConsistencyLock` within `agents/site_auditor_v2/modules/report_layer.ps1`.
- Artifact paths/entrypoints were not changed (`AUDIT_SUMMARY.json`, `ACTION_SUMMARY.json`, `ACTION_REPORT.txt`, `failure_summary.json`).

## Risks/blockers
- This patch is limited to report-layer logic; it assumes upstream callers pass/derive audit truth counts consistently.
- Full end-to-end SITE_AUDITOR_V2 runtime replay is not available in this task context, so validation focused on static/script-level checks.
