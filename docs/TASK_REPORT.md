## Summary
- Repaired SITE_AUDITOR runtime catch-path recovery so empty/null exception messages now fall back to raw error text from `$_ | Out-String`.
- Extended catch-path extraction to capture `Exception`, `InvocationInfo`, and `ScriptStackTrace` prior to failure-reason synthesis.
- Enforced non-empty runtime error messaging by applying layered fallbacks (`Exception.Message` -> raw error -> error record string -> stable runtime fallback text).
- Added explicit trace logging for raw error payload using `[TRACE] RAW ERROR: ...` to preserve forensics when exception message is blank.
- Updated failure-core fact resolver to include raw error-record fallback before default message application.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Repair scope applied only in runtime failure handling and failure-core extraction within `agents/gh_batch/site_auditor_cloud/agent.ps1`.

## Risks/blockers
- Runtime execution validation was not performed in-container because `pwsh` availability is not guaranteed here.
- Behavioral confirmation depends on next SITE_AUDITOR batch run emitting non-empty diagnostic error text from the updated catch path.
