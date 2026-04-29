## Summary
- Applied a surgical fix in report layer ACTION_SUMMARY status resolution to enforce FAIL precedence.
- Ensured a FAIL run/status_label can no longer produce ACTION_SUMMARY.status = CLEAN.
- Kept output shape and existing fields unchanged.
- Did not touch agent.ps1 or any other layer files.
- Performed parser and runtime verification commands as requested.

## Changed files
- `agents/site_auditor_v2/modules/report_layer.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- `agents/site_auditor_v2/modules/report_layer.ps1` now computes `ACTION_SUMMARY.status` with this precedence:
  1) `FAIL` when run/report status indicates failure,
  2) `DEFECT` when defects exist,
  3) `LIMITATION_ONLY` when only limitations exist,
  4) `CLEAN` otherwise.
- Entrypoint remains unchanged: `agents/site_auditor_v2/agent.ps1`.

## Risks/blockers
- None identified for this scoped patch.
