## Summary
- Added a structured `operator_memory_bridge.self_explanation` block in `RUN_REPORT.json` so each run explicitly explains: what the agent is, what happened, minimal system map, one next step, and forbidden actions.
- Updated `REPORT_EN.txt` and `REPORT_RU.txt` generation to print the required operator-grade sections with actionable PASS/PASS_WITH_LIMITS/FAIL language and checked-vs-not-checked scope.
- Enriched `AGENT_MAP.md` output with a dedicated “SYSTEM MAP (MINIMAL)” section and concrete file pointers for operator orientation.
- Extended `run_report.schema.json` to require/validate the new self-explanation contract under `operator_memory_bridge`.
- Kept scope limited to reporting artifacts and contracts; no audit logic, coverage behavior, workflow, or runtime refactor changes.

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
- No full live LINK-mode run was executed in this environment; validation here is static (syntax/contract checks) rather than end-to-end artifact generation.
- `agent.ps1` contains multiple post-output blocks; only reporting text/contract data were adjusted, but future consolidation should be handled as a dedicated refactor task.
