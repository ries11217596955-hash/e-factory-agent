## Summary
Hardened the SITE_AUDITOR output-contract assembly path in scoped functions by precomputing scalar/array/map values before payload literals, removing inline conditional expressions from report-contract hashtables, and stabilizing count/join operations with explicit array coercion in both JSON and text report builders.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Scoped agent file: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Hardened functions:
  - `Build-MetaAuditBriefLines`
  - `Write-RunForensicsReports`
  - `Write-OperatorOutputs`
- Output contracts/reports covered by hardening:
  - `reports/RUN_REPORT.json`
  - `reports/RUN_REPORT.txt`
  - `reports/ARTIFACT_MANIFEST.json`
  - `reports/FAILURE_SUMMARY.json` / `reports/SUCCESS_SUMMARY.json`
  - `reports/REMEDIATION_PACKAGE.json`
  - `reports/HOW_TO_FIX.json`
  - `reports/run_manifest.json`

## Risks/blockers
- No end-to-end SITE_AUDITOR PowerShell runtime execution was performed in this environment, so final validation for runtime traversal beyond `Write-RunForensicsReports` must be confirmed in CI or the operator pipeline run.
