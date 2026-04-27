## Summary
Added a minimal decision engine for `site_auditor_v2` that converts existing audit artifacts into an actionable `decision` block in `RUN_REPORT.json` with `core_problem`, `p0` (max 3), and `do_next` (max 3).

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/lib/decision.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator: `agents/site_auditor_v2/agent.ps1`
- New decision helper library: `agents/site_auditor_v2/lib/decision.ps1`
- Decision output location in artifact: `<run output root>/RUN_REPORT.json` under `decision.core_problem`, `decision.p0`, `decision.do_next`

## Risks/blockers
- PowerShell runtime is not available in this environment (`pwsh: command not found`), so runtime execution of the updated agent could not be performed locally.
- Decision heuristics are intentionally minimal and deterministic by design; they do not replace existing report-layer synthesis and are scoped only to required actionable output.
