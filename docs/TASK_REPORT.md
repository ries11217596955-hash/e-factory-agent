## Summary
Executed PHASE 4 / STEP 14A (compatibility-first) by extracting `Build-DecisionLayer` from `agent.ps1` into a dedicated module, preserving the rich lower-snake-case decision contract as the primary return, and isolating the legacy uppercase collapse contract into a separate adapter function (`Convert-ToLegacyDecisionShape`) without changing downstream output flow.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1` (new)
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.
- Moved function block from `agent.ps1` to `modules/decision_build.ps1`:
  - `Build-DecisionLayer`
- Extracted legacy contract collapse into dedicated adapter in new module:
  - `Convert-ToLegacyDecisionShape`

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Added module import path: `agents/gh_batch/site_auditor_cloud/modules/decision_build.ps1`
- Runtime call flow now (temporary parity path):
  - `$decisionRich = Build-DecisionLayer(...)`
  - `$decision = Convert-ToLegacyDecisionShape($decisionRich)`
- Downstream output contract and operator output flow unchanged.

## Risks/blockers
- Blocker: PowerShell runtime is unavailable in this container (`pwsh`/`powershell` not installed), so runtime parity checks for `RUN_REPORT.json`, `FAILURE_SUMMARY.json`, bundled `REPORT.txt`, `final_status`, and `failed_step` could not be executed locally.
- Risk: while code path preserves legacy adapter usage downstream by design, full FAIL-parity must be validated on a PowerShell-capable runner.
