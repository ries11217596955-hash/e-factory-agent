# TASK_REPORT

## Summary
- Extracted the Site Auditor V3 `operator_control` ordered data-block from module output ownership code into a dedicated helper builder function.
- Added `New-SiteAuditorV3OperatorControlBlock` in `agents/site_auditor_v3/lib/operator_control.ps1` with the same ordered structure and values as before.
- Updated `agents/site_auditor_v3/modules/07_output.ps1` to dot-source the helper and call the builder while preserving 07_output as RUN_REPORT composer.
- Kept RUN_REPORT shape unchanged for `operator_control` and did not alter decision, fallback, next_step, packaging, diagnostic, or self_build logic.
- No protected paths or forbidden module files were modified.

## Changed files
- `agents/site_auditor_v3/modules/07_output.ps1`
- `agents/site_auditor_v3/lib/operator_control.ps1`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v3/run.ps1` (unchanged).
- Output owner remains `agents/site_auditor_v3/modules/07_output.ps1` (still composes RUN_REPORT).
- New helper path: `agents/site_auditor_v3/lib/operator_control.ps1`.

## Risks/blockers
- Dot-sourcing assumes `agents/site_auditor_v3/lib/operator_control.ps1` remains present and loadable at runtime.
- Any future edits to operator control contract must be kept synchronized with RUN_REPORT consumers expecting the current shape.
