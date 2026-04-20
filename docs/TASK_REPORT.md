## Summary
Extracted only the file I/O helper functions from `agent.ps1` into a new module file and dot-sourced that module from `agent.ps1` in compatibility-first mode (no logic edits outside extraction).

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/util_io.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- Function definitions moved (code extraction only):
  - `Ensure-Dir`
  - `Reset-Dir`
  - `Write-JsonFile`
  - `Write-TextFile`
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Added module import path in entrypoint script: `. "$PSScriptRoot/modules/util_io.ps1"`.
- New module file path: `agents/gh_batch/site_auditor_cloud/modules/util_io.ps1`.

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this environment (`pwsh`/`powershell` not found), so runtime fail-parity validation could not be executed here.
- Risk: fail-parity status is unverified in this environment until script is executed where PowerShell is available.
