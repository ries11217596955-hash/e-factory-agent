## Summary
Implemented PROMOTED_ROUTE_CONSUMPTION_PACK v0.1 by introducing a pre-audit route bootstrap discovery path and a canonical audit selection handoff so capture/reconcile/decision share one route truth source.

## Changed files
- agents/site_auditor_v3/contracts/module_registry.json
- agents/site_auditor_v3/modules/03_5_route_bootstrap.ps1
- agents/site_auditor_v3/modules/03_7_audit_selection.ps1
- agents/site_auditor_v3/modules/06_decision.ps1
- agents/site_auditor_v3/modules/07_output.ps1
- agents/site_auditor_v3/modules/08_route_feedback.ps1

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v3/run.ps1`
- Pre-audit route discovery bootstrap now executes via `03_5_route_bootstrap`.
- Canonical audit selection now finalized in `03_7_audit_selection` before `04_capture`.
- Post-decision `08_execution` remains in pipeline for action-driven execution/capability workflow.

## Risks/blockers
- No blocker encountered.
- Residual risk: external discovery source variability may still change promoted set sizes across targets; canonical routing now guarantees consistency across capture/reconcile/decision for whichever promoted/baseline set is selected.
