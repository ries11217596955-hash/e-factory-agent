## Summary
Extracted generic conversion/debug helper functions from `agents/gh_batch/site_auditor_cloud/agent.ps1` into `modules/util_convert.ps1` and `modules/util_debug.ps1`, then dot-sourced those modules from `agent.ps1` in compatibility-first mode without intentional logic changes.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/util_convert.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/util_debug.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Function definitions moved (extracted from `agent.ps1`):
  - `Get-DebugValueSample`
  - `Get-ObjectShapeSummary`
  - `Convert-ToIntSafe`
  - `Convert-ToBoolSafe`
  - `Convert-ToObjectArraySafe`
  - `Normalize-ToArray`
  - `Normalize-CollectionShape`
  - `Add-UniqueString`
  - `Convert-ToStringArraySafe`
  - `Convert-ToStringKeyDictionarySafe`
  - `Convert-ToHashtableSafe`

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Added module imports in entrypoint script:
  - `. "$PSScriptRoot/modules/util_convert.ps1"`
  - `. "$PSScriptRoot/modules/util_debug.ps1"`
- New module file paths:
  - `agents/gh_batch/site_auditor_cloud/modules/util_convert.ps1`
  - `agents/gh_batch/site_auditor_cloud/modules/util_debug.ps1`

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this environment (`pwsh` and `powershell` commands not found), so required fail-parity runtime validation could not be executed locally.
- Risk: parity outputs (`final_status`, `failed_step`, `last_success_stage`, artifact counts) are unverified until run in a PowerShell-capable environment.
