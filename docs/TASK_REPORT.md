## Summary
- Restored report artifact handling so `REPORT_EN.txt` and `REPORT_RU.txt` are explicitly tracked as stable output artifacts.
- Switched produced-artifacts base directory to run-scoped output (`output/<run_id>/`) so artifact discovery aligns with canonical output layout.
- Added report files to required produced-artifact list to keep them visible in `produced_artifacts`.
- Added safe report-copy guards in legacy HUMAN_REPORT copy blocks to prevent `COPY_FAILED` logging when source files are not yet present.
- Ensured fail-path execution also invokes post-output generation, so user-facing reports are generated for both successful and failed runs.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Canonical report artifact directory: `agents/site_auditor_v2/output/<run_id>/`.
- Report generation path on completion/failure: `Invoke-PostOutput -OutputDir $outputRoot -RunReportPath $runReportPath` in `agents/site_auditor_v2/agent.ps1`.
- Produced artifacts assembly: `Get-FinalProducedArtifacts` in `agents/site_auditor_v2/agent.ps1`.
- Root-level mirror for quick access: `agents/site_auditor_v2/REPORT_EN.txt` and `agents/site_auditor_v2/REPORT_RU.txt` written from canonical output at end of run.

## Risks/blockers
- `agent.ps1` contains multiple historical HUMAN_REPORT blocks; this task minimized edits and guarded copy behavior, but the duplicated legacy blocks remain and may warrant later cleanup.
- No full live target-site audit run was executed in this task, so validation is limited to static and local script checks.
