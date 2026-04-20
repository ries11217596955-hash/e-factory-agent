## Summary
Extracted source-audit logic from `agent.ps1` into `modules/source_audit.ps1` in compatibility-first mode without changing workflow entrypoint behavior.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/source_audit.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Functions moved from `agent.ps1` to `modules/source_audit.ps1`:
  - `New-SourceLayer`
  - `Get-SourceSummary`
  - `Invoke-SourceAuditRepo`
  - `Invoke-SourceAuditZip`

## Current entrypoints/paths
- Workflow-facing entrypoint remains: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- New module path: `agents/gh_batch/site_auditor_cloud/modules/source_audit.ps1`.
- Entrypoint now dot-sources source module via `. "$PSScriptRoot/modules/source_audit.ps1"`.

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this container (`pwsh`/`powershell` not found), so execution parity checks could not be run here.
- Risk: required fail-parity assertions (`final_status`, `failed_step`, `last_success_stage`, `final_stage`, artifact generation, screenshot package count) must be validated in a PowerShell-capable runner.
