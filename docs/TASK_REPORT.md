## Summary
- Root cause isolated: report synthesis had multiple unguarded indexed accesses in REPORT_LAYER (e.g. selected cluster/action/payload/action chain checks), and empty collections could trigger index failures that surfaced as `REPORT_LAYER_EXCEPTION`.
- Added reusable report-safety helpers in `modules/report_safe_helpers.ps1`: `Get-FirstOrNull`, `Test-HasItems`, `Resolve-RepresentativeExamples`, and `Resolve-DominantSurface`.
- Extracted report-layer computations into `modules/report_layer.ps1`:
  - system problem derivation (`New-SystemProblemFromFindings`)
  - decision summary derivation (`New-DecisionSummaryFromSystemProblem`)
  - action summary derivation (`New-ActionSummaryFromDecision`)
  - human report payload assembly (`New-HumanReportPayloads`)
  - consistency checks (`Test-ReportConsistencyLock`)
- Hardened partial artifact truth discipline: HUMAN_REPORT and ACTION_SUMMARY are no longer auto-filled on failed runs, and REPORT_LAYER failures remove those artifacts from `produced_artifacts`/`linked_artifacts` truth surfaces.
- Hardened failure contract clarity: failure summary/notes now include failing phase and operator-readable note (`fetch failure`, `surface context failure`, `report layer failure`, `internal exception`).

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Imported new report modules.
  - Replaced report-layer inline synthesis with module-driven calls.
  - Removed raw index access in report paths and switched to safe helper usage.
  - Added phase-aware failure details in report/failure output.
  - Tightened fail-state artifact publication behavior.
- `agents/site_auditor_v2/modules/report_safe_helpers.ps1` (new)
  - Added null-safe/empty-safe collection helpers for report synthesis.
- `agents/site_auditor_v2/modules/report_layer.ps1` (new)
  - Added extracted report-layer orchestration helpers and consistency lock checks.
- `docs/TASK_REPORT.md`
  - Updated with PACK S2 stabilization/extraction report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report-layer boundary now centralized in:
  - `agents/site_auditor_v2/modules/report_layer.ps1`
  - `agents/site_auditor_v2/modules/report_safe_helpers.ps1`
- Output contract paths are unchanged; only fail-state artifact truth handling changed.

## Risks/blockers
- Runtime verification is limited by local environment tooling availability (PowerShell runtime + external network target behavior).
- This patch intentionally avoids feature expansion; only report stabilization and orchestration thinning were changed.
- Future edits must keep `failurePhase` updates aligned with phase mapping to preserve truthful fail classification.

## Rollback instructions by file/block
1. `agents/site_auditor_v2/agent.ps1`
   - Remove imports for `modules/report_safe_helpers.ps1` and `modules/report_layer.ps1`.
   - Restore previous inline report-layer synthesis block (system problem, decision summary, action summary, payload assembly, consistency checks).
   - Restore previous fail-state artifact publication behavior if needed.
2. `agents/site_auditor_v2/modules/report_safe_helpers.ps1`
   - Delete file and restore direct collection/index logic in `agent.ps1`.
3. `agents/site_auditor_v2/modules/report_layer.ps1`
   - Delete file and restore inline report-layer logic in `agent.ps1`.
4. `docs/TASK_REPORT.md`
   - Restore prior task report revision from git history.
