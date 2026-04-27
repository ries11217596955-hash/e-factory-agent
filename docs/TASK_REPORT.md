## Summary
Applied a narrow PS5.1-safe array-shape fix for SITE_AUDITOR_V2 so single-item outputs do not collapse into scalars in the report contract boundary. The contract helper now uses unary-comma array wrapping, and final report assignments for `findings` and `produced_artifacts` are normalized through the same helper.

## Changed files
- agents/site_auditor_v2/modules/report_contract.ps1
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`
- Contract boundary updated: `agents/site_auditor_v2/modules/report_contract.ps1`
- Reporting updated: `docs/TASK_REPORT.md`

## Risks/blockers
- Runtime execution was not performed in this environment, so end-to-end artifact upload verification is pending operator run.
- Scope intentionally excludes route extraction, RECON, capture, workflow, and report semantics changes.
