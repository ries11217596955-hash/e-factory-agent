## Summary
- Reworked SITE_AUDITOR_V2 produced artifact contract to be derived strictly from files that actually exist under `agents/site_auditor_v2/output/<run_id>/`.
- Removed pre-declared artifact insertion from `Get-FinalProducedArtifacts`, eliminating false positives where non-existent files were listed in `produced_artifacts`.
- Added explicit warnings (`EXPECTED_ARTIFACT_MISSING`) for expected-but-absent non-critical files so missing outputs are visible without creating self-contradictory contracts.
- Added critical guard: if `RUN_REPORT.json` is absent from scanned filesystem artifacts, the flow now throws `RUN_REPORT_ARTIFACT_MISSING`.
- Scope remained limited to produced-artifacts assembly/report generation contract behavior and task reporting, with no workflow or audit-logic changes.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Produced artifacts are assembled in `Get-FinalProducedArtifacts` (`agents/site_auditor_v2/agent.ps1`) from filesystem scan results gathered by `Get-ProducedArtifacts` against `agents/site_auditor_v2/output/<run_id>/`.
- Expected artifact visibility is now warning-based (`EXPECTED_ARTIFACT_MISSING`) inside `Get-FinalProducedArtifacts`.
- Critical artifact enforcement remains explicit for `RUN_REPORT.json` via `RUN_REPORT_ARTIFACT_MISSING` throw in `Get-FinalProducedArtifacts`.
- Report contract population call sites remain unchanged and continue assigning `$report.produced_artifacts` from `Get-FinalProducedArtifacts`.

## Risks/blockers
- This task was validated statically (script inspection + syntax check) rather than full end-to-end SITE_AUDITOR_V2 runtime execution.
- If downstream consumers implicitly relied on pre-declared-but-missing artifact names, they will now only see existing files and warning logs.
