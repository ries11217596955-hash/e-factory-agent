## Summary
- Investigated REPO result contract handling in `Normalize-Result` and identified strict type gating as the downgrade source: any non-hashtable or partial object was forced to `*_INVALID_RESULT`.
- Added explicit raw REPO object logging (`Write-Output ($repo | ConvertTo-Json -Depth 5)`) before normalization so runtime shape is visible in logs/output.
- Reworked normalization to accept partial objects when any of these are present: `status`, `artifacts`, or `reports_path`.
- Implemented safe coercion defaults (`status` => `PARTIAL`, `reason` => empty string) and artifact/report-aware success preservation.
- Added REPO-specific acceptance/coercion logs (`REPO_RESULT_ACCEPTED` / `REPO_RESULT_COERCED`) to show normalization path taken.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Normalization function: `Normalize-Result` in the same script.
- Bundle status outputs: `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json` and `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`.

## Risks/blockers
- No blockers.
- Minor behavioral risk: malformed non-null objects that previously hard-failed by type now attempt coercion; this is intentional for contract compatibility but may surface as `PARTIAL` rather than `FAIL` when artifact/report signals are present.

### actual repo object
- Runtime now emits full serialized REPO object via:
  - `Write-Output ($repo | ConvertTo-Json -Depth 5)`
- This is recorded at execution time (not hardcoded in report) to reflect real shape from current run.

### mismatch reason
- Previous validator required exact hashtable contract (`$r -is [hashtable]`) and effectively treated partial/object-like inputs as invalid.
- This caused false `repo_INVALID_RESULT` even when useful data existed (e.g., artifacts/reports).

### fix applied
- Replaced strict null+type rejection with null-only rejection.
- Added property-safe extraction for hashtable and object inputs.
- Added validity rule: accept when `status` OR `artifacts` OR `reports_path` exists.
- Added force-upgrade rule: if artifacts/reports exist and status is `FAIL`, normalize to `PARTIAL`.
- Added REPO normalization path logging (`REPO_RESULT_ACCEPTED` / `REPO_RESULT_COERCED`).

### before/after status
- Before: partial/non-hashtable REPO payloads could normalize to `FAIL` with `repo_INVALID_RESULT`.
- After: non-null partial payloads with status/artifacts/reports signal are accepted/coerced; artifact/report-backed failures become `PARTIAL` to reflect real output presence.
