## Summary
- Increased default route coverage budget in LINK mode from 5 to 18 selected routes to raise deterministic sample depth.
- Increased shallow route extraction sampling window from 10 to 30 candidate routes so selection can reliably fill the higher default budget.
- Updated visual target selection default `MaxPages` from 5 to 18 to keep module defaults aligned with orchestrator defaults.
- Preserved deterministic, priority-ranked route selection strategy and existing capture/report contracts (no CLI or report schema changes).
- Kept changes scoped to route selection/sampling and task reporting only.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/stage_route_keys.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator: `agents/site_auditor_v2/agent.ps1`
- Route extraction stage: `agents/site_auditor_v2/modules/stage_link_fetch.ps1` (consumed by orchestrator call-site)
- Route target selection: `agents/site_auditor_v2/modules/stage_route_keys.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- End-to-end acceptance metrics (selected count, screenshot totals, confidence status) require a full runtime execution against a live target site; not executed in this environment.
- Increasing extraction/sample defaults increases network and capture workload; this is bounded (30 extraction candidates, 18 selected routes) but may extend run time on slower targets.
