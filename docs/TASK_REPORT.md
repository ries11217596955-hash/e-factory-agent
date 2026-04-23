## Summary
Fixed the PowerShell 5.1 failure-path artifact merge crash by materializing the internal `System.Collections.Generic.List[string]` into a plain array before appending failure artifacts, preserving artifact names and failure finalization semantics.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Change scope limited to failure finalization artifact list assembly in `agents/site_auditor_v2/agent.ps1`.

## Risks/blockers
- No full runtime execution was performed in this environment; validate with a failure-path run to confirm absence of `Argument types do not match` and expected `RUN_REPORT.json` finalization output.
