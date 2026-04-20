## Summary
Executed PHASE 4 / STEP 12 (compatibility-first) by extracting only remediation-layer logic from `agents/gh_batch/site_auditor_cloud/agent.ps1` into `agents/gh_batch/site_auditor_cloud/modules/decision_remediation.ps1`, wiring the new module import in the existing entrypoint, and intentionally keeping `Write-SelfRepairArtifacts` in `agent.ps1` due filesystem/report contract coupling risk.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/decision_remediation.ps1` (new)
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Moved function blocks from `agent.ps1` to `modules/decision_remediation.ps1`:
  - `Build-PrimaryRemediationPackage`
  - `Get-DecisionRepairHint`
- Left in place (by design for compatibility):
  - `Write-SelfRepairArtifacts`

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Added module path: `agents/gh_batch/site_auditor_cloud/modules/decision_remediation.ps1`
- Decision orchestration and output contract flow remain in `agent.ps1`.

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this container (`pwsh`/`powershell` not installed), so runtime FAIL-parity verification could not be executed locally.
- Risk: required parity checks (`RUN_REPORT.json`, `FAILURE_SUMMARY.json`, bundled `REPORT.txt`, and expected fail-stage contract values) still need validation on a PowerShell-capable runner.
