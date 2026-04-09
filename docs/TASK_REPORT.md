## Summary
- Root cause: the script returned a complex PowerShell object (`$manifest`), which can trigger host/runner argument binding/type mismatch failures (`Argument types do not match`) in some execution paths.
- Fix: replaced object return with a JSON output model in the final section by serializing `$manifest` using `ConvertTo-Json -Depth 5` and emitting it via `Write-Output`.
- Implemented SSOT file write for manifest JSON to `audit_bundle/master_summary.json`.
- Added companion JSON write to `audit_bundle/audit_bundle_summary.json`.
- Added manifest output telemetry log `MANIFEST_OUTPUT_JSON_OK`, and now terminate with explicit `exit $exitCode` to keep exit code behavior deterministic (`0` for non-crash outcomes, `1` only for runtime crash path).

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle runner entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Fix location in file: finalization section after `Invoke-WritingStage`.
- JSON manifest output path (SSOT): `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`.
- Companion summary path: `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`.

## Risks/blockers
- `audit_bundle_summary.json` is now overwritten at finalization with the manifest JSON shape; any consumer expecting the previous bundle-status-only JSON structure from Stage 3 should validate compatibility.
- Command consumers expecting a returned PowerShell object must now parse JSON from stdout instead.
