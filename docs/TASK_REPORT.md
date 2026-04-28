## Summary
- Added a strict `=== OPERATOR CONTROL ===` block at the top of both `REPORT_EN.txt` and `REPORT_RU.txt` outputs in `Invoke-PostOutput`.
- Made the status line self-sufficient by pairing `PASS / PASS_WITH_LIMITS / FAIL` with a plain-language explanation from `operator_memory_bridge.self_explanation.what_happened_in_this_run.status_meaning_plain`.
- Added explicit checked counters (routes, screenshots, executed layers), one-step next action, a single limitation line, and a constrained DO NOT line (2–3 forbidden moves).
- Kept report generation human-readable (no JSON rendering) and ensured the control block is emitted before all existing findings/details sections.
- Preserved audit behavior and coverage; this change only affects report text assembly from existing `RUN_REPORT` fields.

## Changed files
- agents/site_auditor_v2/lib/post_output.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Report text renderer: `agents/site_auditor_v2/lib/post_output.ps1` (`Invoke-PostOutput`).
- Operator task log: `docs/TASK_REPORT.md`.

## Risks/blockers
- No full LINK-mode execution was run in this environment, so validation is static (code-path review) rather than artifact-based.
- `layers executed` count is derived from `system_map_minimal` entries filtered by `limit/limited` text, so malformed upstream strings can reduce count precision.
