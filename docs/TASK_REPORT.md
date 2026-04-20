## Summary
Applied HOTFIX STEP 14C-R with a minimal patch scoped to the `contradiction_summary_build` block in `Build-DecisionLayer`. Added a local compatibility shim that materializes `SourceLayer` and `LiveLayer` into plain hashtables and `MissingInputs` into `string[]` immediately before calling `Build-ContradictionLayer`, preserving all downstream builder/output behavior.

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
- Final parity assertions (`final_stage`, `last_success_stage`, report artifact presence) require execution in an environment with PowerShell installed and the project’s normal run inputs.
