# TASK_REPORT

## Summary
- Extracted Site Auditor V3 decision action and next step selection into a dedicated helper builder function.
- Added `New-SiteAuditorV3DecisionNextStepBlock` in `agents/site_auditor_v3/lib/decision_next_step.ps1`.
- Updated `agents/site_auditor_v3/modules/07_output.ps1` to dot-source the helper and keep composing RUN_REPORT with the same `decision_action` and `next_step` fields.
- Preserved the existing precedence for `post_build_decision.decision_action`, `build.next_action`, `decision.decision_action`, and fallback decision action.
- No protected paths or forbidden module files were modified.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `agents/site_auditor_v3/lib/decision_next_step.ps1`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v3/run.ps1` (unchanged).
- Output owner remains `agents/site_auditor_v3/modules/07_output.ps1` (still composes RUN_REPORT).
- New helper path: `agents/site_auditor_v3/lib/decision_next_step.ps1`.

## Risks/blockers
- Dot-sourcing assumes `agents/site_auditor_v3/lib/decision_next_step.ps1` remains present and loadable at runtime.
- Any future edits to decision action or next step precedence must preserve RUN_REPORT consumers expecting the current shape.
