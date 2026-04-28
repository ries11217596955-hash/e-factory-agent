## Summary
- Hardened low-confidence PASS semantics in `SITE_AUDITOR_V2` so completed runs can still be `PASS` while being explicitly labeled `PASS_WITH_LIMITATIONS` via `status_label` when `audit_confidence=LOW`.
- Added explicit `confidence_reason`, `next_verification_step`, and `forbidden_next_steps` fields to `RUN_REPORT` output.
- Propagated the same limitation context into `ACTION_SUMMARY` (`status_label`, `confidence_reason`, `next_verification_step`, `forbidden_next_steps`) so action output cannot imply strong success.
- Updated generated human text report status display to prefer `status_label` and include confidence reason + next verification step.
- Kept scope minimal: no refactor, no capture logic changes, no route extraction changes, no workflow edits.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator entrypoint: `agents/site_auditor_v2/agent.ps1`
- Report output paths impacted: `RUN_REPORT.json`, `ACTION_SUMMARY.json`, `REPORT_EN.txt`, `REPORT_RU.txt`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Could not execute end-to-end validation in this container because `pwsh` runtime is unavailable; behavior should be verified in CI/runtime by generating fresh artifacts.
