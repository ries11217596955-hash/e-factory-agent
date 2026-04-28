## Summary
- Adjusted SITE_AUDITOR_V2 artifact validation timing so REPORT_LAYER can compute `produced_artifacts` without failing before OUTPUT writes final files.
- Kept expected artifact warnings (`EXPECTED_ARTIFACT_MISSING`) intact during pre-output scans.
- Added explicit post-OUTPUT critical validation for `RUN_REPORT.json`, `REPORT_EN.txt`, and `REPORT_RU.txt`.
- Added a post-write validation call immediately after `Write-RunReportBounded` in both success and fail completion paths.
- Preserved existing audit/report/recon/route logic and avoided broad refactoring.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- `Get-FinalProducedArtifacts` now supports optional strict mode via `-ValidateCriticalFinalArtifacts` and only throws in that mode.
- REPORT_LAYER and other pre-output call sites still use non-strict artifact scans for planning and diagnostics.
- Final strict artifact validation runs after `Write-RunReportBounded` in both completion paths to enforce post-write filesystem truth.

## Risks/blockers
- Validation was verified through static checks and PowerShell parse checks; no full end-to-end live website audit run was executed in this environment.
- If an environment writes `REPORT_EN.txt` / `REPORT_RU.txt` asynchronously after `Write-RunReportBounded`, strict validation may fail earlier (intended for deterministic lifecycle enforcement).
