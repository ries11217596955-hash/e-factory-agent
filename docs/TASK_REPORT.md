## Summary
- Root crash cause fixed: `Get-SurfaceExpectation` could receive a blank/whitespace `SurfaceType` from report-layer paths, and parameter binding on mandatory string input caused runtime failure. All call sites now normalize to `UNKNOWN`, and `Get-SurfaceExpectation` now applies its own defensive normalization fallback.
- Surface/context logic was extracted from `agents/site_auditor_v2/agent.ps1` into `agents/site_auditor_v2/modules/surface_context.ps1` to stop monolith growth while preserving existing behavior.
- Internal exceptions are no longer always reported as `LINK_FETCH_FAILED`; failure classification now maps by phase (`LINK_FETCH_FAILED`, `SURFACE_CONTEXT_EXCEPTION`, `REPORT_LAYER_EXCEPTION`, `INTERNAL_EXCEPTION`).
- Report synthesis now normalizes weak/missing surface values to `UNKNOWN` in dominant-surface and representative-example flows, preventing context-note lookup crashes.
- UNKNOWN discipline is enforced: context-specific findings are not escalated for `UNKNOWN` surfaces the same way as confidently classified surfaces.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Removed inline PACK 5 surface-context function bodies.
  - Imported `modules/surface_context.ps1`.
  - Normalized surface values before all `Get-SurfaceExpectation` calls.
  - Added phase-aware failure classification in top-level catch.
  - Added report-layer guards for dominant surface and representative examples.
  - Added UNKNOWN gating for context-specific defect escalation.
- `agents/site_auditor_v2/modules/surface_context.ps1`
  - New extracted module containing:
    - `Resolve-SurfaceType`
    - `Get-NormalizedSurfaceType`
    - `Get-SurfaceExpectation`
    - media/article/directory guard helpers
- `docs/TASK_REPORT.md`
  - Updated for PACK S stabilization + extraction status.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Surface-context boundary introduced: `agents/site_auditor_v2/modules/surface_context.ps1` is now the primary source for surface normalization/expectation rules.
- Existing report artifacts and output paths unchanged.

## Risks/blockers
- Runtime execution validation is limited in this environment if `pwsh` is unavailable.
- This patch is intentionally stabilization-only; no new audit capabilities were added.
- Failure classification now depends on execution phase markers; future large flow moves should keep phase updates aligned.

## Rollback instructions by file/block
1. `agents/site_auditor_v2/agent.ps1`
   - Remove dot-source import for `modules/surface_context.ps1`.
   - Restore previous inline surface-context functions.
   - Revert phase-based catch classification to previous single-code behavior.
   - Revert surface normalization guards in dominant/report example paths.
2. `agents/site_auditor_v2/modules/surface_context.ps1`
   - Remove file and restore prior inlined logic in `agent.ps1`.
3. `docs/TASK_REPORT.md`
   - Restore prior report revision from git history.
