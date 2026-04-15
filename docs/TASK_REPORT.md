## Summary
- Repaired parser-breaking JSON-style escaped quotes in the decision serialization block of `agent.ps1`.
- Fixed `core_problem` newline/carriage-return normalization strings to valid PowerShell string syntax.
- Fixed newline join expressions for `P0`, `DO NOW`, and `DO AFTER` summary sections to valid PowerShell string syntax.
- Verified there are no remaining `\"` escape sequences in `agent.ps1`.
- Kept scope minimal to syntax repair only; no behavior redesign.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Decision object construction and executive summary generation now use valid PowerShell quote syntax in the same existing block.
- No workflow, deployment, or runtime entrypoint paths were changed.

## Risks/blockers
- PowerShell runtime (`pwsh`/`powershell`) is unavailable in this container, so parser validation could not be executed locally.
- Validation was limited to static scan confirming no remaining `\"` escape patterns in `agent.ps1`.
