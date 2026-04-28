## Summary
- Converted `REPORT_EN.txt` and `REPORT_RU.txt` output format to operator-first structure at the top of the report.
- Added required top sections in order: WHAT THIS RUN MEANS, SYSTEM STATE, KEY LIMITATION (ONE), NEXT STEP (ONE ONLY), and DO NOT DO.
- Kept exactly one explicit next step sourced from `operator_memory_bridge.self_explanation.next_step_one_only`.
- Added optional detailed findings after the decision-first header so operators can act without opening JSON files.
- Preserved audit logic and coverage behavior; only post-output report text composition was changed.

## Changed files
- agents/site_auditor_v2/lib/post_output.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Human text report generator: `agents/site_auditor_v2/lib/post_output.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- No full LINK-mode run was executed in this environment; validation is based on static inspection of report assembly.
- Layer extraction in the top section depends on existing `system_map_minimal` and `checked_vs_not_checked` content quality from `RUN_REPORT`.
