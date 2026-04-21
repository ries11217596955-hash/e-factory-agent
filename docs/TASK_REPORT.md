## Summary
- Task: SITE_AUDITOR repair batch for truth-boundary stabilization after `DECISION_BUILD` PASS at `OPERATOR_OUTPUT_CONTRACT`.
- Traced the failing boundary in `agents/gh_batch/site_auditor_cloud/agent.ps1` output assembly path (`Write-OperatorOutputs` → `Write-RunForensicsReports` / fallback contract path).
- Repaired stage/node resolution so stale `live.summary.failure_stage` values (for example `PAGE_QUALITY_BUILD`) no longer override a real `OPERATOR_OUTPUT_CONTRACT` failure when `last_success_stage=DECISION_BUILD`.
- Updated failure-node projection so `failure_node` now follows the resolved failed stage across `RUN_REPORT.json`, `FAILURE_SUMMARY.json`, and fallback truth packaging.
- Hardened catch-path messaging so generic `Unknown failure while running SITE_AUDITOR.` is replaced with stage-aware contract-boundary context when the original exception message is empty.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Repaired boundary: `agents/gh_batch/site_auditor_cloud/agent.ps1` (`Resolve-FailureStageForOutput`, `Get-FallbackTruthEvidence`, `Write-RunForensicsReports`, main catch block near operator output contract).

## Risks/blockers
- Runtime verification is blocked in this container because `pwsh`/`powershell` are unavailable, so a full SITE_AUDITOR execution bundle could not be produced locally.
- Next operator bundle should confirm: `failed_step` and `failure_node` are aligned with `OPERATOR_OUTPUT_CONTRACT` for post-`DECISION_BUILD` contract failures, and generic unknown failure text is no longer emitted.
