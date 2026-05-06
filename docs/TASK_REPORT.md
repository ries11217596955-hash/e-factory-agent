## Summary
- Added wrapper-run artifact manifest generation to `agents/site_auditor_v3/tests/run_and_validate.sh`, producing `ARTIFACT_MANIFEST.json` in the run directory before archive creation.
- Manifest now records run identity, run directory, wrapper packaging mode, deliverable path, produced files, expected files, missing expected files, extra files, and UTC creation timestamp.
- Updated wrapper packaging rewrite logic so `RUN_REPORT.packaging` includes `manifest`, `produced_files_count`, and `missing_expected_files` sourced from `ARTIFACT_MANIFEST.json`.
- Kept raw-run behavior unchanged (`RAW_RUN` remains emitted by module `07_output` and wrapper-only manifest logic remains in the test wrapper).
- Scope remained limited to the requested wrapper script plus mandatory task report update.

## Changed files
- `agents/site_auditor_v3/tests/run_and_validate.sh`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Raw run entrypoint remains `agents/site_auditor_v3/run.ps1`; raw runs continue to report `packaging.mode = RAW_RUN` and do not claim wrapper manifest creation.
- Wrapper packaging flow remains `agents/site_auditor_v3/tests/run_and_validate.sh`; it now writes `ARTIFACT_MANIFEST.json` inside `agents/site_auditor_v3/runs/<run_id>/` before ZIP/TAR creation.
- Deliverables remain under `agents/site_auditor_v3/_deliver/`.

## Risks/blockers
- End-to-end acceptance could not be executed in this environment because `pwsh` is not installed, so wrapper-run PASS and archive content assertions were not runtime-verified here.
- Manifest `deliverable` is computed as the ZIP target path pre-packaging; on hosts using tar fallback this path may differ from the actual deliverable file extension.
