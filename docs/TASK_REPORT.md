## Summary
Added a mandatory `operator_memory_core` block to LINK-mode `RUN_REPORT.json`, anchored to deterministic run-state evidence and populated with fixed operator identity/system-goal fields plus stage/focus/stability/capability fields derived from existing report truth sources.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode only).
- RUN_REPORT contract path remains `agents/site_auditor_v2/contracts/run_report.schema.json`.
- `RUN_REPORT.json` now includes both `operator_feed` and mandatory `operator_memory_core`.
- `operator_memory_core` fields are deterministic and constrained to current capabilities: identity/system anchors, current stage/focus, stable/unstable state, learned limits, risk, and one next capability.

## Risks/blockers
- `operator_memory_core` intentionally excludes speculative interpretation and uses empty defaults where state cannot be derived.
- Capability limitations remain explicit to reduce operator-context drift risk and prevent accidental over-claiming.
