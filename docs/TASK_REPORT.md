## Summary
- Added micro-split instrumentation labels inside `warnings/step02/manual_safe_walk` to isolate the exact failing statement in `Build-DecisionLayer`.
- Kept the original step02 context label/expression and inserted statement-level checkpoints `step02a` through `step02e` exactly at list creation, source enumeration, item add, fallback scalar add, and warning-items enumeration.
- Did not change helper functions, input/output boundaries, or logic in step03/step04/step06.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry point unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Active instrumentation path now includes:
  - `warnings/step02/manual_safe_walk`
  - `warnings/step02a/create_warningItems_list`
  - `warnings/step02b/enumerate_normalizedWarnings`
  - `warnings/step02c/add_item_to_warningItems`
  - `warnings/step02d/add_fallback_scalar`
  - `warnings/step02e/enumerate_warningItems`

## Risks/blockers
- Runtime verification is still required: a fresh `FAILURE_SUMMARY.json` must show one of `step02a`..`step02e` for precise localization.
- If failure still reports only `warnings/step02/manual_safe_walk`, runtime likely executed stale code or instrumentation path was not loaded.
