## Summary
- Patched `SITE_AUDITOR_V2` artifact contract handling so final `produced_artifacts` is now deterministically merged before each final `RUN_REPORT` write, guaranteeing `RUN_REPORT.json` declaration even when file scanning happens before final write.
- Enforced stable required artifact declarations in final `produced_artifacts`: `RUN_REPORT.json`, `ACTION_REPORT.txt`, `ACTION_SUMMARY.json`, `AUDIT_SUMMARY.json`, `LINK_SUMMARY.json`, and `ROUTES_SUMMARY.json`.
- Added conditional inclusion logic to final `produced_artifacts` for `visual_manifest.json` (when present), `screenshots/*` (when present), and `failure_summary.json` (when `status=FAIL` or file exists).
- Kept changes scoped to artifact list construction only; no workflow, route/report decision logic, or audit findings logic changes.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary orchestrator entrypoint: `agents/site_auditor_v2/agent.ps1`
- Artifact contract finalization path: `Get-FinalProducedArtifacts` and all final `$report.produced_artifacts` assignments before `Write-RunReportBounded`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Could not execute end-to-end run/package validation in this container because `pwsh` is unavailable, so GitHub Actions regression confirmation and output ZIP content confirmation must be validated in CI/runtime.
