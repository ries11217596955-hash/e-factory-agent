## Summary
- Root cause: `Get-RepoScreenshotManifest` returned the manifest list wrapped in an extra array (`@($manifest)`), which led to mismatched object shape during assembly and triggered `Argument types do not match`.
- Fix: changed `Get-RepoScreenshotManifest` to return the list directly (`return $manifest`) so consumers iterate consistent manifest entries.
- Assembly hardening: replaced pipeline-based relative path extraction with explicit foreach casting to `[string]` for stable artifact list construction.
- Added debug output before assembly artifact extraction: `SCREENSHOT_MANIFEST_COUNT=<count>`.
- Impact: assembly now handles screenshot manifest items deterministically and remains stable through bundle/JSON writing.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry script: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Screenshot manifest source roots: `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/reports` and `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/outbox`.
- Bundle artifacts destination path: `agents/gh_batch/site_auditor_cloud/audit_bundle/bundle_artifacts/`.
- Summary outputs: `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json` and `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`.

## Risks/blockers
- No blockers identified for this scoped fix.
- If upstream code relies on the previous wrapped return shape, those callers would need to align to the direct list contract (not observed in current repository references).
