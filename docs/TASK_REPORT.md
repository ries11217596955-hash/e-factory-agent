## Summary
- Normalized low-confidence pass vocabulary in `SITE_AUDITOR_V2` from `PASS_WITH_LIMITATIONS` to `PASS_WITH_LIMITS`.
- Aligned both `RUN_REPORT.execution_report.status_detail` and `ACTION_SUMMARY.status_label` to the same canonical value for limited passes.
- Preserved strong-pass behavior (`PASS`) and overall run status contract (`RUN_REPORT.status` remains `PASS` for successful runs).
- Kept scope strictly limited to the allowed files with no workflow/runtime routing logic edits.
- This targets the regression check requiring `execution_report.status_detail` to be either `PASS` or `PASS_WITH_LIMITS`.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator entrypoint: `agents/site_auditor_v2/agent.ps1`
- Report outputs affected by vocabulary normalization: `RUN_REPORT.json`, `ACTION_SUMMARY.json`
- Task report location: `docs/TASK_REPORT.md`

## Risks/blockers
- Could not run a full PowerShell end-to-end execution in this environment; `pwsh` is not available for local runtime verification.
