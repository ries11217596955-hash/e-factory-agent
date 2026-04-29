## Summary
- Added a safe post-write copy step so `ACTION_REPORT.txt` is mirrored from `output/<run_id>/ACTION_REPORT.txt` to `agents/site_auditor_v2/ACTION_REPORT.txt`.
- Kept existing output folder generation logic unchanged.
- Applied the same safe copy behavior to the fallback ACTION_REPORT write path.
- Ensured missing source file does not crash the run by guarding copy with `Test-Path` and `-ErrorAction SilentlyContinue`.
- No modules, routing, or runtime flow were refactored.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Primary report write path remains: `agents/site_auditor_v2/output/<run_id>/ACTION_REPORT.txt`.
- Added mirror copy target for CI compatibility: `agents/site_auditor_v2/ACTION_REPORT.txt`.

## Risks/blockers
- Low risk: change is limited to guarded file-copy operations after existing ACTION_REPORT writes.
