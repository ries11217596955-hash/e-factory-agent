# TASK_REPORT

## Summary
- Task: `SITE_AUDITOR — TRACE ONLY FOR NORMALIZE-LIVEROUTES (NO FIX MODE)`.
- Mode: `TRACE ONLY` (no bug fix attempted).
- Scope kept to `agents/gh_batch/site_auditor_cloud/agent.ps1`, `reports/route_normalization_trace.json`, and this report.
- Added phase-accurate route normalization tracing metadata for failure visibility at the exact failing phase.
- Final state: `TRACE_ADDED_NEEDS_RUNTIME_RUN`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `reports/route_normalization_trace.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Function targeted: `Normalize-LiveRoutes`.
- Mandatory artifact path created: `reports/route_normalization_trace.json`.

## Risks/blockers
- Runtime execution is still required to populate route-level trace entries from live manifest data.
- Container does not provide `pwsh`, so full runtime validation could not be executed here.
- No remediation/fix has been applied, by design.

## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/README.md`
- `docs/REPO_LAYOUT.md`

## TRACE_ONLY_MODE
- `ENFORCED`

## PHASES_ADDED
- `raw_route_entry`
- `route_after_string_key_normalization`
- `route_path_extraction`
- `route_signal_fields`
- `drop_count_computation`
- `normalized_route_output`

## FAILURE_VISIBILITY_BEFORE
- Failures in the per-route block were always recorded as `normalized_route_output`, even when the throw originated earlier.
- Failure payload did not include the exact `failing_phase`/`expression` fields requested.

## FAILURE_VISIBILITY_AFTER
- Per-route failures are now recorded against the active phase (`route_after_string_key_normalization`, `route_path_extraction`, `route_signal_fields`, or `normalized_route_output`).
- Failure payload now includes:
  - `failing_phase`
  - `operation_label`
  - `expression`
  - `left_type` / `right_type`
  - `left_value_sample` / `right_value_sample`
  - `stack_hint_if_available`

## FIX_APPLIED = NONE
- Confirmed. This change set is observability-only instrumentation.

## VALIDATION_RESULT
- Static checks only: script parses and git diff reviewed.
- Runtime trace population pending next live run.
