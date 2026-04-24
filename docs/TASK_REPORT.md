## Summary
Implemented RECON prep localization markers and reconciliation prep collection-shape hardening for SITE_AUDITOR_V2 LINK runtime blocker analysis.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: agents/site_auditor_v2/agent.ps1
- Reconciliation prep stage: agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1
- Reporting artifact: docs/TASK_REPORT.md

## Risks/blockers
- Runtime was not executed by Codex in this task, so marker visibility and failure-boundary movement are unverified in-process.
- Remaining runtime issues outside reconciliation prep and marker placement may still block LINK flow.
