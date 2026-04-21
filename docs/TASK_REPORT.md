## Summary
- Task: SITE_AUDITOR tool-fix batch to restore diagnostic runner helper availability for `Build-DecisionLayer` forensics.
- Identified helper source: `Convert-ToDecisionWarningStringArray` is defined in `agents/gh_batch/site_auditor_cloud/agent.ps1` and consumed by `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`.
- Added tool-only helper shim file and loaded it from `decision_build_forensics.ps1` before module imports so the forensics harness has required function availability.
- Kept the change bounded to the diagnostic tool path; no production entrypoints, workflows, or decision business logic files were modified.
- Attempted forensic rerun, but this environment has no PowerShell runtime (`pwsh`/`powershell` unavailable), so JSON artifact re-generation cannot be executed here.

## Changed files
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics_helpers.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Forensic harness path: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- Tool helper shim path: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics_helpers.ps1`
- Production entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`

## Risks/blockers
- Runtime verification is blocked by missing PowerShell runtime in this environment (`pwsh` and `powershell` commands are unavailable).
- Because execution is blocked, the next forensic JSON artifact path and any potential subsequent failing node must be confirmed in an environment with PowerShell installed.
