## Summary
- Hardened `NEXT STEP` output in `Invoke-PostOutput` so report text always emits exactly one executable move.
- Replaced direct passthrough of `operator_memory_bridge.self_explanation.next_step_one_only` with a deterministic action string using `[Action] + [Target] + [Reason]`.
- Forced target to concrete truth artifact `RUN_REPORT.json` and concrete field path `operator_memory_bridge.next_operator_posture.what_to_inspect_next[0]`.
- Kept existing status, limitation, and detail sections unchanged; only `NEXT STEP` composition logic was modified.
- Preserved compatibility by falling back to `why_confidence` when no upstream next-step reason exists.

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
- The generated reason currently embeds upstream text verbatim; if upstream reason strings are long, `NEXT STEP` may become verbose (but remains executable and single-action).
