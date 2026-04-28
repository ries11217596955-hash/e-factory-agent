## Summary
- Hardened AGENT_MAP generation content to explicitly state agent identity, active product scope, execution mode/layer, and a core module/file responsibility map.
- Extended RUN_REPORT `operator_memory_bridge.next_operator_posture` with an explicit `recommended_tool` and `forbidden_drifts` contract for operator-grade handoff discipline.
- Updated the run report schema to require and validate the new operator handoff fields (`recommended_tool`, `forbidden_drifts`).
- Upgraded `REPORT_EN.txt` / `REPORT_RU.txt` generation to always explain: agent identity, scope, mode/layer, module responsibility map, run outcome, PASS_WITH_LIMITS meaning, what to inspect next, one recommended next move, and forbidden next moves.
- Kept changes limited to reporting/mapping scope; no changes to audit coverage, route sampling, workflows, or new audit features.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/contracts/run_report.schema.json
- agents/site_auditor_v2/lib/post_output.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator: `agents/site_auditor_v2/agent.ps1`
- Report schema contract: `agents/site_auditor_v2/contracts/run_report.schema.json`
- Human text report generator: `agents/site_auditor_v2/lib/post_output.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- No full live LINK-mode run was executed in this environment, so runtime rendering of the enriched output files is validated statically by code inspection only.
- Because `agent.ps1` contains repeated report/AGENT_MAP blocks, future cleanup should de-duplicate carefully without changing runtime semantics.
