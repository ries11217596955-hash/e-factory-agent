## Summary
Fixed the `Write-RunReportBounded` count-shape bug in `site_auditor_v2` by adding a PS5.1-safe `Get-SafeCount` helper and replacing direct `.Count` access on the report findings collection. This prevents crashes when `findings` is null, scalar, string, singleton object, or non-array collection.

Exact fixed expression:
- ` $findingCount = [int]$reportBound.findings.Count`
- replaced with
- ` $findingCount = [int](Get-SafeCount -Value $reportBound.findings)`

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator: `agents/site_auditor_v2/agent.ps1`
- Target function: `Write-RunReportBounded`
- Output artifact path (unchanged): `<run output root>/RUN_REPORT.json`

## Risks/blockers
- No end-to-end Codespaces rerun was executed in this environment; validation here is static and syntax-level.
- Change is intentionally minimal and bounded to count-shape handling in `Write-RunReportBounded`; no Playwright, RECON, routing, or workflow paths were modified.
