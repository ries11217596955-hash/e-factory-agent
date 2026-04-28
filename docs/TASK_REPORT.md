## Summary
- Removed speculative artifact declaration in `SITE_AUDITOR_V2` by replacing predeclared artifact expectations with an append-only produced-artifact registry populated from real files only.
- Added explicit CAPTURE-layer post-write registration for `visual_capture_input.json` and `visual_manifest.json`.
- Added REPORT-layer post-write registration for `REPORT_CONTRACT_DIAG.json`.
- Updated final artifact aggregation to use only files that exist on disk (scan + append-only registry), while preserving strict final critical validation behavior.
- Kept validation, checks, and audit logic intact while changing only artifact lifecycle timing and ownership boundaries.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- `Get-FinalProducedArtifacts` now builds from append-only registry entries and filesystem scan results only, with no speculative expected-artifact list.
- CAPTURE layer registers artifacts only after write completion (`visual_capture_input.json`, `visual_manifest.json`).
- REPORT layer registers `REPORT_CONTRACT_DIAG.json` only after the diagnostic file exists.
- OUTPUT/finalization paths continue to aggregate existing files and run strict critical validation after write completion.

## Risks/blockers
- Full runtime execution and end-to-end LINK audit were not run in this environment; behavior was validated via source-level inspection.
- `pwsh` is not available in this container, so PowerShell parser/runtime checks could not be executed locally.
