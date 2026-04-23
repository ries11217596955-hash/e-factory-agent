## Summary
Applied a minimal PowerShell 5.1-safe type fix in `Invoke-EvidenceReconciliation()` so the screenshot relative path normalization uses a matching `string,string` overload for `.Replace()`.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Modified scope limited to one normalization line inside `Invoke-EvidenceReconciliation()`.

## Risks/blockers
- Runtime execution was not performed in this environment, so acceptance needs validation in a normal run.
- If downstream logic depends on platform-specific separators, behavior should now be deterministic via explicit string conversion.
