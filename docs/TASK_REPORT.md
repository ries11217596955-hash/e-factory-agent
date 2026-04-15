## Summary
- Root cause classified as **created but not copied + copied to wrong place + validator ignored absence** for screenshot packaging.
- Restored canonical packaging contract by collecting runtime screenshots from `repo/reports/screenshots` and writing them into final bundle root `screenshots/`.
- Added visual artifact contract accounting (`screenshots_expected`, `screenshots_packaged`, `screenshots_missing`) and persisted it into both `RUN_REPORT.json` and `audit_result.json`.
- Enforced failure behavior: when visual audit is active and screenshots are missing/unpackaged, bundle status is forced to `FAIL` with explicit visual contract error.
- Updated artifact metadata to reference canonical packaged screenshot root (`screenshots`) instead of runtime-only `reports/screenshots`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Runtime screenshot producer remains: `agents/gh_batch/site_auditor_cloud/capture.mjs` → `reports/screenshots/*.png`
- Canonical packaged screenshot root (new contract): `agents/gh_batch/site_auditor_cloud/screenshots/`
- Canonical run report path remains: `agents/gh_batch/site_auditor_cloud/reports/RUN_REPORT.json`
- Legacy mirror remains available: `agents/gh_batch/site_auditor_cloud/audit_bundle/`

## Risks/blockers
- Runtime execution test is blocked because PowerShell (`pwsh`/`powershell`) is not installed in this environment.
- End-to-end ZIP validation is blocked by missing PowerShell runtime; validation here is static/code-path inspection only.
