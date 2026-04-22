## Summary
Upgraded the LINK-mode `RUN_REPORT.json` output contract with a deterministic audit answer layer so each run now states what is wrong, why it matters, and what to do next without expanding crawler/interaction scope.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/site_auditor_v2/agent.ps1` (LINK mode only).
- RUN_REPORT contract path remains `agents/site_auditor_v2/contracts/run_report.schema.json`.
- New report-layer outputs are generated inside `RUN_REPORT.json`: `executive_answer`, `findings`, `priority_summary`, `page_verdicts`, `business_impact`, `next_action_contract`, hardened `operator_handoff`, and explicit `report_mode` (`CLEAN`/`PROBLEM`).

## Risks/blockers
- Findings are intentionally bounded to currently available evidence artifacts (`ROUTES_SUMMARY.json`, `AUDIT_SUMMARY.json`, `ACTION_SUMMARY.json`, `visual_manifest.json`, `RUN_REPORT.json`) and do not infer interaction or conversion behavior.
- No crawler depth, screenshot engine behavior, or decision automation was added; deeper interpretation remains out of scope until additional evidence layers exist.
