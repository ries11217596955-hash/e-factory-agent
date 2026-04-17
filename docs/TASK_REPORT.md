## Summary
- Performed a focused forensic audit of `Build-DecisionLayer` and its direct helper dependency `Get-DecisionRepairHint` in `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Confirmed the crash boundary aligns with `DECISION_BUILD` before the post-return writeback block, matching `last_success_stage = INPUT_VALIDATION`.
- Identified a strict parameter type mismatch risk in `Get-DecisionRepairHint` for `-LiveSummary` when `Build-DecisionLayer` passes a normalized ordered dictionary/object.
- Applied one minimal bounded fix: relaxed `Get-DecisionRepairHint` parameter type from `[hashtable]` to `[object]` to match real call shapes without changing logic.
- Kept scope strictly limited to the requested file plus this required task report.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint audited: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Affected execution path: `Build-DecisionLayer` → `Get-DecisionRepairHint` call path inside stage `DECISION_BUILD`.

## Risks/blockers
- No runtime PowerShell execution verification was performed in this environment because `pwsh` is unavailable; validation was static source-level forensics.
- Diagnosis assumes runtime payloads can provide non-hashtable dictionary-like objects (e.g., ordered dictionaries) to `Get-DecisionRepairHint`; patch is intentionally minimal and type-tolerant.
