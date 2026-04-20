## Summary
Performed PHASE 4 / STEP 14C controlled rich decision contract repair in `Build-DecisionLayer` only. Kept the legacy adapter path intact (`Build-DecisionLayer` rich output + `Convert-ToLegacyDecisionShape` legacy mapping), and repaired rich-path population for contradiction/diagnosis/remediation/repair-hint/closeout using the dedicated module builders.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Decision builder path unchanged: `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- Legacy adapter path unchanged:
  - `Build-DecisionLayer(...)` returns rich lower-snake-case decision object.
  - `Convert-ToLegacyDecisionShape(...)` still provides downstream legacy decision shape.

## Risks/blockers
- PowerShell runtime verification is blocked in this container because `pwsh` is unavailable, so full runtime parity checks for generated artifacts and final status fields could not be executed locally.
- `Build-DecisionLayer` now relies on module-level builders being loaded in the same runtime (existing module import contract); if module loading order changes externally, this can impact execution.
