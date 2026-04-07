## Summary
Hardened SITE_AUDITOR layer handling to eliminate runtime crashes from missing properties by introducing a unified live layer constructor and enforcing defensive normalization for both source and live layers before decision/output construction. `Invoke-LiveAudit` now always returns a normalized layer object in all paths (BASE_URL missing, capture/runtime failure, and success), so downstream property reads (including `root`) cannot throw.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- SITE_AUDITOR entrypoint: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Live capture script dependency (unchanged path): `agents/gh_batch/site_auditor_cloud/capture.mjs`
- Output artifacts (unchanged paths):
  - `agents/gh_batch/site_auditor_cloud/reports/audit_result.json`
  - `agents/gh_batch/site_auditor_cloud/reports/HOW_TO_FIX.json`
  - `agents/gh_batch/site_auditor_cloud/outbox/REPORT.txt`

## Risks/blockers
- Live capture failures are now represented as normalized `live` findings/warnings instead of throwing immediately; this preserves FAIL evaluation but slightly changes the failure surface from exception-first to data-first in `Invoke-LiveAudit`.
- End-to-end mode verification (`REPO`/`ZIP`/`URL`) depends on external runtime inputs (`TARGET_REPO_PATH`, ZIP payload, and reachable `BASE_URL`) and was not fully reproducible in this isolated environment.
