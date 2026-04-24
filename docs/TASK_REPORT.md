## Summary
Added a PS5.1-safe report finding contract gate to normalize REPORT_LAYER findings to required shape and emit a diagnostic artifact (`REPORT_CONTRACT_DIAG.json`) before downstream report consumption.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/report_contract.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Contract module: `agents/site_auditor_v2/modules/report_contract.ps1` (`Normalize-FindingContract`)
- Normalization point: report layer, single call immediately after `$report.findings` binding and before operator-feed/report-layer consumption.
- Diagnostic artifact: `agents/site_auditor_v2/output/<run_key>/REPORT_CONTRACT_DIAG.json`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- No full end-to-end PowerShell runtime execution was performed in this environment, so live verification of generated `RUN_REPORT.json` and `REPORT_CONTRACT_DIAG.json` outputs was not run here.
- Gate normalizes required contract fields only (minimal scope) and does not refactor RECON/ROUTE/OUTPUT stages.
