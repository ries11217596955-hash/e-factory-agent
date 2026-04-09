## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-existing)
- `docs/README.md`
- `docs/FINAL_ROOT_CLOSEOUT.md`

## Summary
- Fixed false `FAIL` classification in `Normalize-Result` for SITE_AUDITOR REPO results by making normalization data-aware.
- Data presence now follows requested rule: `screenshots_count > 0` OR non-empty `reports_path` OR non-empty `outbox_path`.
- When status is missing/incomplete and data is present, result is now coerced to `PARTIAL` with reason `${name}_COERCED_FROM_DATA`.
- Preserved existing `FAIL` behavior for null/empty results and no-data invalid payloads.
- Added required REPO diagnostics: `REPO_HAS_DATA`, `ORIGINAL_OBJECT=<json>`, and `NORMALIZED_STATUS`.

## CHANGE SUMMARY
- Updated only validator logic in `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` (`Normalize-Result`) with no pipeline, Playwright, CI, or bundle structure changes.

## BEFORE / AFTER (FAIL → PARTIAL)
- **Before:** Missing/empty `status` could normalize to `FAIL` with `${name}_INVALID_RESULT` even when REPO payload still had output data markers.
- **After:** Missing/empty `status` with REPO data now normalizes to `PARTIAL` with `${name}_COERCED_FROM_DATA`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Only `Normalize-Result` behavior was adjusted.

## VALIDATION evidence
- Static inspection confirms:
  - `REPO_HAS_DATA` derived from `screenshots_count`, `reports_path`, and `outbox_path`.
  - Missing status + data path returns `PARTIAL` + `${name}_COERCED_FROM_DATA`.
  - Required logs present: `REPO_HAS_DATA`, `ORIGINAL_OBJECT=...`, `NORMALIZED_STATUS`.

## Risks/blockers
- No blockers.
- Low-risk behavior change limited to status normalization for schema-incomplete but data-backed REPO payloads.
