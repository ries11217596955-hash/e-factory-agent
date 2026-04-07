## Summary
Fixed a `SITE_AUDITOR` output contract regression introduced after Phase C by adding a guaranteed artifact finalization path in `agent.ps1`. Main execution now records caught errors and always runs an `Ensure-OutputContract` function in `finally`, which guarantees `reports/audit_result.json`, `outbox/REPORT.txt`, and exactly one done marker (`DONE.ok` or `DONE.fail`) even when upstream logic fails.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Downstream outputs preserved:
  - `agents/gh_batch/site_auditor_cloud/reports/audit_result.json`
  - `agents/gh_batch/site_auditor_cloud/outbox/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.ok`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.fail`
  - existing optional reports from normal flow remain unchanged (`HOW_TO_FIX.json`, `00_PRIORITY_ACTIONS.txt`, `01_TOP_ISSUES.txt`, `11A_EXECUTIVE_SUMMARY.txt`, `run_manifest.json`).

## Risks/blockers
- `DONE.ok` is still driven by overall computed `PASS` status, so if a downstream write failure occurs after status computation, contract output will remain deterministic but final result may be `DONE.fail` due to caught exception (intended for safety).
- Full end-to-end verification for all modes (`REPO`, `ZIP`, `URL`) remains environment/input dependent; local checks focused on contract guarantees under failure path.
