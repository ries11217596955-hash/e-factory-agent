## Summary
- Task: SITE_AUDITOR tool-fix batch for forensic artifact finalization after `decision_layer_complete`.
- Investigated the post-decision path in `decision_build_forensics.ps1` and isolated the remaining high-risk point to final artifact/decision JSON serialization.
- Applied a bounded compatibility fix by normalizing complex runtime objects into JSON-safe scalar/dictionary/array shapes before `ConvertTo-Json`.
- Kept the change strictly inside the forensic diagnostic tool path; no production agent/runtime logic was modified.
- Updated forensic output flow so final diagnostic artifact emission is resilient across mixed object types that can trigger `Argument types do not match` during serialization.

## Changed files
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Production entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Repaired diagnostic path: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1` (post-decision artifact finalization + optional decision JSON emission).

## Risks/blockers
- Runtime verification is blocked in this container because neither `pwsh` nor `powershell` is installed; the forensic script cannot be executed locally here.
- Final validation (artifact JSON emitted, no post-decision argument-type failure) must be confirmed in an environment with PowerShell available.
