## Summary
Applied a minimal PS5.1-safe guard in `Write-RunReportBounded` so optional `finding.evidence` is accessed only when the property exists and is non-null, and `evidence_refs` is materialized only when that nested property exists.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- RUN_REPORT writer path: `Write-RunReportBounded` in `agents/site_auditor_v2/agent.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Full end-to-end runtime execution to verify `OUTPUT: SERIALIZE_DONE`, `OUTPUT: WRITE_DONE`, and `RUN_REPORT.json` creation was not executed in this environment.
- Change is intentionally narrow and does not modify `Convert-RunReportValue`, report schema, or add any new fields.
