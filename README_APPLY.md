# SITE_AUDITOR_V2 Manual Repair Pack

## Replace files in repo
Copy these files into the repository preserving paths:

1. `agents/site_auditor_v2/agent.ps1`
2. `agents/site_auditor_v2/modules/report_contract.ps1`
3. `docs/TASK_REPORT.md`

## What this fixes
- `REPORT_CONTRACT_DIAG.json` was declared in `produced_artifacts` but only written under `output/<run_key>/`, so the workflow could not stage it from `agents/site_auditor_v2/REPORT_CONTRACT_DIAG.json`.
- REPORT_LAYER normalized `$report.findings`, but downstream logic kept using stale pre-normalized arrays (`$allFindings`, `$defectFindings`, `$limitationFindings`), so missing-property failures could continue.

## Expected next run
- `REPORT_CONTRACT_DIAG.json` exists at `agents/site_auditor_v2/REPORT_CONTRACT_DIAG.json`.
- Artifact staging should not fail with `Listed artifact missing: REPORT_CONTRACT_DIAG.json`.
- If another issue appears, it should be a new downstream defect, not the same contract-diagnostic artifact failure.
