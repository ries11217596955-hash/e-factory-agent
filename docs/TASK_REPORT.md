## Summary
- Root cause: `Normalize-Result` used strict validation behavior that produced `*_INVALID_RESULT` failure outcomes even when REPO payloads still carried useful output data.
- Before behavior: a missing/empty `status` on non-null REPO results could still end in failure, masking valid artifact-backed runs.
- After behavior: validation is now data-aware (`artifacts_present`, `reports_path`, `outbox_path`) and coerces missing-status results with data to `PARTIAL` using `${name}_COERCED_FROM_DATA`.
- Added mandatory REPO debug output to prove data detection at runtime: `REPO_HAS_DATA=<bool>` and serialized REPO payload JSON.
- Kept scope minimal to requested validator logic and report update only.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint script remains: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Updated function remains: `Normalize-Result` in the same script.
- No workflow, execution stage, Playwright stage, or bundle structure changes were made.

## Risks/blockers
- No blockers.
- Intentional behavior shift: when `status` is missing but REPO data exists, status becomes `PARTIAL` instead of `FAIL` to reflect real output state.
- Proof condition addressed: payloads with data markers (`artifacts_present=$true` and/or non-empty `reports_path`/`outbox_path`) are no longer marked `FAIL` solely due to missing status.
