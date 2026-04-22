## Summary
Consolidated operator-facing context so `operator_memory_bridge` is the single source of truth for identity, state, learning, must-read contract, and next-operator actions in LINK-mode `RUN_REPORT.json` output.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode).
- RUN_REPORT schema remains `agents/site_auditor_v2/contracts/run_report.schema.json`.
- Top-level `truth_files` and `read_order` context blocks are removed from report construction; must-read context lives in `operator_memory_bridge.must_read_contract`.
- `operator_memory_bridge.next_operator_posture` now carries `must_do_before_next_task`, `what_to_inspect_next`, and `do_not_do_yet`.
- `operator_handoff` is retained only as compatibility mirror (`deprecated: true`, `mirrors_operator_memory_bridge: true`) and is populated from `operator_memory_bridge` values.

## Risks/blockers
- Compatibility mirror fields remain to avoid downstream contract breakage; consumers should migrate reads to `operator_memory_bridge` only.
- This change assumes downstream readers tolerate additional mirrored legacy keys (`deprecated`, `mirrors_operator_memory_bridge`, mirrored next-step arrays).
