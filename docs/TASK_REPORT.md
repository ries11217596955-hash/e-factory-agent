# TASK_REPORT

## Summary
- Task: `SITE_AUDITOR — NORMALIZE-LIVEROUTES PIPELINE TRACE (ROOT-CAUSE AUDIT)`.
- Scope honored: only `Normalize-LiveRoutes` instrumentation and direct local trace helper wiring in `agents/gh_batch/site_auditor_cloud/agent.ps1`, plus this report file.
- Added per-route phase tracing with explicit phase/status/object-shape sampling, and persisted runtime artifact `reports/route_normalization_trace.json`.
- No speculative product-level changes were made outside the locked normalization scope.
- Final state for this change set: `TRACE_ADDED_NEEDS_NEXT_RUN`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Target function: `Normalize-LiveRoutes`.
- Added runtime report artifact path: `reports/route_normalization_trace.json`.

## Risks/blockers
- Runtime proof is still required to isolate the exact failing operation from live data.
- This environment has no `pwsh`, so local execution validation cannot be completed here.
- If failure happens before route-level loop completion, some later phases can be absent by design (status records still present for reached phases).

## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/README.md`
- `docs/REPO_LAYOUT.md`

## CURRENT_HYPOTHESIS
- The persistent `Argument types do not match` likely originates within route-entry normalization operations (object/field coercion path) rather than top-level dropped-count math, because previous arithmetic hardening did not clear the blocker.

## WHY_PREVIOUS_FIXES_LOOK_SECONDARY
- Prior fixes targeted safe key handling and count arithmetic boundaries.
- The blocker remained at `ROUTE_NORMALIZATION`, indicating the root mismatch is likely inside a per-route phase where heterogeneous route shapes are transformed.
- Existing `route_normalization_debug.json` captured singular failure context, but not multi-phase per-entry progression needed to pinpoint earliest failing transform.

## TRACE_PHASES_ADDED
- `raw_route_entry`
- `route_after_string_key_normalization`
- `route_path_extraction`
- `route_signal_fields`
- `drop_count_computation`
- `normalized_route_output`

Each phase snapshot now records:
- `phase_name`
- `route_index`
- `route_path_if_available`
- `object_type`
- `keys`
- `short_value_sample`
- `status` (`ok`/`skipped`/`failed`)

Failure snapshots additionally include:
- `operation_label`
- `left_type` / `right_type`
- `left_value_sample` / `right_value_sample`
- `error_message`
- `stack_hint`

## EXACT_FAILING_PHASE
- `NOT_YET_ISOLATED` (requires next runtime execution with new trace artifact).

## FIX_APPLIED
- `NONE` (trace-first instrumentation only; no speculative root-cause patch applied).

## VALIDATION_RESULT
- Static validation only:
  - Script updated successfully.
  - No runtime proof available in this container (`pwsh` unavailable).

## NEXT_BLOCKER_IF_ANY
- Need one runtime execution producing `reports/route_normalization_trace.json` to confirm exact failing phase and operation label under real manifest data.
