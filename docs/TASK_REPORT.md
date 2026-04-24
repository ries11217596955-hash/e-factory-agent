## Summary
Restricted RUN_REPORT enumerable normalization in `Convert-RunReportValue` to explicit safe collection types (`System.Array` and `System.Collections.IList`) to prevent over-broad enumeration of non-data objects during serialization on PowerShell 5.1.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Serialization normalization path: `Convert-RunReportValue` in `agents/site_auditor_v2/agent.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- End-to-end runtime verification for `WRITE_DONE` and `RUN_REPORT.json` creation was not executed in this environment.
- Change is intentionally minimal and scoped only to enumerable normalization; no RECON, route extraction, report semantics, or module refactoring were modified.
