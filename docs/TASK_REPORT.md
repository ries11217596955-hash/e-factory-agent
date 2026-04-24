## Summary
Introduced a single PS5.1-safe findings normalization contract in `SITE_AUDITOR_V2` report flow so every finding has `recommended_action`, `evidence`, and `evidence.evidence_refs` before downstream report-layer usage.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Normalization point: report layer, immediately after `$report.findings` binding and before operator-feed/report-layer consumption.
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- No full PowerShell runtime execution was performed in this environment, so end-to-end verification of all report outputs was not run here.
- This task intentionally adds normalization only and does not remove existing scattered guards (deferred per task instruction).
