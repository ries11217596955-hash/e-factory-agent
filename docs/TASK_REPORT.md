## Summary
Repaired SITE_AUDITOR_V2 report contract integration after artifact-first analysis of runpack/logs. The previous contract gate wrote `REPORT_CONTRACT_DIAG.json` only under the run output folder while `produced_artifacts` declared the deterministic root file, causing artifact staging failure. It also normalized `$report.findings` but downstream REPORT_LAYER logic continued using stale pre-normalized finding arrays, allowing missing-property failures such as `recommended_action` to persist.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/report_contract.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Contract module: `agents/site_auditor_v2/modules/report_contract.ps1`
- Diagnostic artifact: `agents/site_auditor_v2/REPORT_CONTRACT_DIAG.json`

## Root cause fixed
1. `REPORT_CONTRACT_DIAG.json` was added to `produced_artifacts` before a deterministic root copy existed.
2. REPORT_LAYER continued to use stale `$allFindings`, `$defectFindings`, and `$limitationFindings` arrays created before normalization.

## Patch behavior
- `REPORT_CONTRACT_DIAG.json` is no longer declared at startup.
- After `Normalize-FindingContract`, the diagnostic file is copied from the run output folder to deterministic root.
- `REPORT_CONTRACT_DIAG.json` is added to `produced_artifacts` only after the root file exists.
- `$allFindings`, `$defectFindings`, and `$limitationFindings` are rebound from normalized `$report.findings` before downstream REPORT_LAYER logic.

## Risks/blockers
- End-to-end GitHub Actions runtime was not executed in this environment.
- Patch is deliberately scoped to report contract integration and artifact staging; RECON, ROUTE, CAPTURE, OUTPUT serialization, workflow, and report semantics were not changed.
