## Summary
- Added a root-level `packaging` object to RUN_REPORT generation in `07_output` so direct `run.ps1` executions are explicitly labeled as `RAW_RUN` with runpack expectation and creation both set to false.
- Updated the validation wrapper script to rewrite RUN_REPORT packaging metadata after archive creation, marking wrapper execution as `WRAPPER_RUN` and recording the produced deliverable path.
- Kept all changes scoped to the two requested V3 files and preserved existing run flow and validator steps.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `agents/site_auditor_v3/tests/run_and_validate.sh`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Raw run entrypoint remains `agents/site_auditor_v3/run.ps1` and now emits default packaging metadata (`RAW_RUN`) in `RUN_REPORT.json`.
- Wrapper flow remains `agents/site_auditor_v3/tests/run_and_validate.sh`, now additionally updating `RUN_REPORT.json` packaging fields after ZIP/TAR creation.
- RUN artifacts remain under `agents/site_auditor_v3/runs/<run_id>/`.

## Risks/blockers
- Runtime validation of PowerShell execution modes and validators could not be executed in this environment unless `pwsh` is available.
- Wrapper metadata currently marks the wrapper artifact note as ZIP-oriented per requirement text, even when tar.gz fallback is used on systems without `zip`.
