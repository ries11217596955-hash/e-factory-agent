## Summary
- Fixed CI validation path desynchronization by enforcing a single-source check of `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json` in the `Validate agent result` workflow step.
- Removed legacy multi-path scanning/fallback validation behavior (`audit_bundle`, `outbox`, recursive report discovery) that caused false-fail behavior despite canonical RUN_REPORT presence.
- Added CI debug traces to print the exact canonical path checked and a targeted listing of `agents/gh_batch/site_auditor_cloud/reports/` when the canonical file is missing.
- Fixed screenshot packaging root in `Invoke-WritingStage` to copy screenshot artifacts under the canonical bundle root (`reports/`) rather than `$PSScriptRoot`.
- Added explicit post-write debug traces for RUN_REPORT existence and packaged screenshot count under bundle root to prove writer/validator synchronization.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Workflow order remains: `run_bundle.ps1` -> upload artifact -> `Validate agent result`.
- Canonical validator SSOT path: `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json`.
- Canonical writer path remains: `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json`.
- Screenshot destination root is now canonical bundle root (`reports/`), e.g. `agents/gh_batch/site_auditor_cloud/reports/screenshots/...`.
- Legacy mirror remains debug-only via copy from canonical bundle to `agents/gh_batch/site_auditor_cloud/audit_bundle/`.

## Risks/blockers
- Full end-to-end GitHub Actions execution is not runnable in this local environment; validation here is based on static workflow/script inspection.
- If upstream screenshot manifest emits unexpected relative paths outside `screenshots/`, copy behavior still follows provided relative paths under bundle root by design.
