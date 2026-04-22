## Summary
Implemented a canonical `operator_memory_bridge` block in LINK-mode `RUN_REPORT.json` output that deterministically unifies static operator identity anchors, dynamic run-state/learning anchors, must-read contract fields, and next operator posture.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode).
- RUN_REPORT schema remains `agents/site_auditor_v2/contracts/run_report.schema.json`.
- `RUN_REPORT.json` now includes mandatory `operator_memory_bridge` as canonical operator-context block while retaining `operator_memory_core` and `operator_handoff` for compatibility.
- `operator_memory_bridge.must_read_contract` now carries `must_read_files`, `read_order`, `first_file_to_open`, `why_read`, and `minimum_context_after_read`.
- `operator_memory_bridge` is seeded with static SSOT identity anchors and dynamic runtime state/learning fields; dynamic fields stay empty when not derivable.

## Risks/blockers
- Compatibility fields are intentionally retained to avoid downstream contract breakage while transitioning canonical context to `operator_memory_bridge`.
- `minimum_context_after_read` is deterministic and constrained to current LINK/report-layer capabilities; deeper interpretation remains explicitly out of scope.
