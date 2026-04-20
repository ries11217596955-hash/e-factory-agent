## Summary
Executed PHASE 4 / STEP 11 (compatibility-first) by extracting only diagnosis-layer logic from `agents/gh_batch/site_auditor_cloud/agent.ps1` into new module `agents/gh_batch/site_auditor_cloud/modules/decision_diagnosis.ps1`, then wiring module import in the existing entrypoint with no decision workflow or contract behavior changes.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/decision_diagnosis.ps1` (new)
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Moved function blocks from `agent.ps1` to `modules/decision_diagnosis.ps1`:
  - `Build-SiteDiagnosisLayer`
  - `Build-MaturityReadinessLayer`
  - `Build-AuditorBaselineCertification`

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Added module path: `agents/gh_batch/site_auditor_cloud/modules/decision_diagnosis.ps1`
- Decision orchestration remains in `Build-DecisionLayer` in the entrypoint; diagnosis-layer functions are now dot-sourced from the module.

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this container (`pwsh`/`powershell` not installed), so runtime FAIL-parity checks and artifact regeneration could not be executed locally.
- Risk: required parity validation still must be run on a PowerShell-capable runner to confirm `RUN_REPORT.json`, `FAILURE_SUMMARY.json`, bundled `REPORT.txt`, and unchanged failure contract values.
