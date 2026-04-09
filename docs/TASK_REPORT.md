## Summary
- Root cause: `run_bundle.ps1` returned a complex PowerShell object (`$manifest`) at script end, which can trigger pipeline/consumer type binding failures such as `Argument types do not match`.
- Fix: replaced the object return path with a JSON output model (`$manifest_json = $manifest | ConvertTo-Json -Depth 5`) and removed object return semantics.
- Added SSOT persistence for summary output by writing JSON text to `audit_bundle/master_summary.json` and also to `audit_bundle/audit_bundle_summary.json`.
- Added explicit manifest success telemetry: `MANIFEST_OUTPUT_JSON_OK`.
- Preserved exit-code contract by terminating with `exit $exitCode` (0 for OK/PARTIAL path, 1 only for runtime crash path via existing `Get-BundleExitCode` logic).

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry script: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Final-output JSON files:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json`
  - `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`
- Finalization behavior: emit JSON string to STDOUT and exit with script exit code.

## Risks/blockers
- `audit_bundle_summary.json` now mirrors `master_summary.json` (same manifest payload); if downstream expects a different schema in bundle summary, consumers should verify assumptions.
- `Out-File -Encoding utf8` may include UTF-8 BOM depending on host PowerShell version; JSON parsers used in downstream CI should tolerate BOM or strip it.
