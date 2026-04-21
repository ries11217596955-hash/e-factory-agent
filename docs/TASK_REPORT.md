## Summary
- Task: SITE_AUDITOR tool-fix batch to restore diagnostic runner helper availability for `Build-DecisionLayer` forensics.
- Confirmed helper source: `Convert-ToDecisionWarningStringArray` is defined in `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics_helpers.ps1` (mirrors production helper behavior used by `modules/decision_build.ps1`).
- Updated `decision_build_forensics.ps1` to require and dot-source the forensics helper file (hard-fail if missing), then assert `Convert-ToDecisionWarningStringArray` is available before module loading.
- Added explicit preflight checks that required decision-build functions are loaded (`Build-DecisionLayer`, `Convert-ToHashtableSafe`, `Convert-ToObjectArraySafe`, `Convert-ToDecisionWarningStringArray`) so missing helper/module availability fails early and clearly in the diagnostic path only.
- Attempted forensic rerun, but this environment has no PowerShell runtime (`pwsh`/`powershell` unavailable), so JSON artifact re-generation cannot be executed here.

## Changed files
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Forensic harness path: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- Forensics helper path: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics_helpers.ps1`
- Production entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`

## Risks/blockers
- Runtime verification is blocked by missing PowerShell runtime in this environment (`pwsh` and `powershell` commands are unavailable).
- Because execution is blocked, generation of a fresh `decision_build_forensics_*.json` artifact must be validated in an environment with PowerShell installed.
