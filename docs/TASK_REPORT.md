## Summary
Implemented REPORT_LAYER localization markers and collection-shape hardening in `SITE_AUDITOR_V2` to address the runtime blocker (`Argument types do not match`) without changing report semantics.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Runtime was **not executed by Codex** in this task, so end-to-end runtime acceptance remains to be verified by operator run.
- Marker instrumentation is deterministic, but any remaining type-shape mismatch outside the touched REPORT_LAYER boundaries could still fail at runtime.
