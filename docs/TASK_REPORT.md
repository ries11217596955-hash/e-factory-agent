## Summary
Extracted bootstrap/context initialization from `agent.ps1` into new `modules/bootstrap.ps1` via `Initialize-SiteAuditorBootstrapContext`, and updated the entrypoint script to consume returned startup state in compatibility-first mode.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/bootstrap.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Initialization logic moved from `agent.ps1` to `modules/bootstrap.ps1`:
  - workspace/base path resolution (`$env:GITHUB_WORKSPACE` vs `$PSScriptRoot`)
  - startup path initialization (`outbox`, `reports`, `runtime`, `zip_extracted`)
  - startup run metadata initialization (`timestamp`, `runStartedAt`, `runId`, defaults)
  - initial stage/status/failure defaults (`currentStage`, `lastSuccessStage`, `status`, `failureReason`)
  - global forensic placeholder initialization (`AuditError`, route/page/decision forensic containers)
  - startup report file list container initialization (`reportFiles`)

## Current entrypoints/paths
- Workflow entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Added module file: `agents/gh_batch/site_auditor_cloud/modules/bootstrap.ps1`.
- Added dot-source import in entrypoint: `. "$PSScriptRoot/modules/bootstrap.ps1"`.

## Risks/blockers
- Blocker: PowerShell runtime is not available in this execution environment (`pwsh`/`powershell` not found), so mandatory fail-parity runtime execution checks could not be run locally.
- Risk: required parity assertions (`final_status`, `failed_step`, `last_success_stage`, `final_stage`, and artifact presence checks) remain unverified until executed in a PowerShell-capable environment.
