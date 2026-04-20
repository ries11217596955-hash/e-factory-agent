## Summary
Applied a bounded patch in `Build-DecisionLayer` (`contradiction_summary_build`) to stop DictionaryEntry shim misuse when preparing contradiction inputs. Source/live contradiction layers now consume native `DictionaryEntry` key/value pairs first, with a safe fallback path only for non-`DictionaryEntry` entries. Output contract flow and downstream builders remain unchanged.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Decision build module touched: `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- Contradiction builder untouched: `agents/gh_batch/site_auditor_cloud/modules/decision_contradictions.ps1`

## Risks/blockers
- Runtime parity execution could not be validated in-container because PowerShell (`pwsh`) is unavailable.
- Requested runtime fields (`final_status`, `failed_step`, `final_stage`, `last_success_stage`) could not be produced from live execution artifacts in this environment.
