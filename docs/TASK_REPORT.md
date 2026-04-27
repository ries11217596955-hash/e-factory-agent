## Summary
- Added a runtime-safe helper `Get-ScriptFailureDiagnostics` to extract structured script failure diagnostics from a PowerShell error record.
- Wired stage exception catch handling to capture script-level diagnostics at failure time, including the most recent report-layer marker.
- Extended `failure_summary.json` payload construction to include exact technical location fields required for debugging stage failures.

## Changed files
- agents/site_auditor_v2/modules/runtime_safe.ps1
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator (behavior unchanged except minimal failure wiring): `agents/site_auditor_v2/agent.ps1`
- Runtime-safe diagnostics helper (new): `agents/site_auditor_v2/modules/runtime_safe.ps1`
- Failure artifact emitted on fail path: `agents/site_auditor_v2/output/<mode>_<hash>/failure_summary.json`

## Risks/blockers
- Could not run an end-to-end PowerShell execution in this container if `pwsh` is unavailable; runtime behavior validation may require execution in the target PowerShell environment.
- Existing fallback `lastResortFailure` object (failure_summary write-failure path) intentionally remains minimal and does not include full diagnostics fields.
