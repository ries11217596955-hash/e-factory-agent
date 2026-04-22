## Summary
Implemented a bounded LINK-mode route-key canonicalization fix in `site_auditor_v2` so selected routes and manifest routes are compared using the same normalized path-only key format. This removes false `COUNTER_INCONSISTENCY` mismatches caused by representation drift (absolute URL vs normalized path) while preserving hard fail behavior for real page-set mismatches. Added explicit normalization error capture so unsafe route values are recorded and excluded from raw cross-format comparison.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Route normalization helpers:
  - `Get-NormalizedRouteResult` (existing normalized route logic)
  - `Get-CanonicalRouteKeyResult` (new single canonical route-key wrapper used by comparison path)
- LINK-mode selected-vs-manifest route set comparison now canonicalizes both sides before mismatch detection and writes normalization diagnostics under `report.capture_summary.counter_mismatch_details`.

## Risks/blockers
- Validation here was code-level/static and did not run a full external LINK capture against a live target.
- Route values that cannot be safely normalized are now treated as `normalization_error`, which intentionally prevents PASS for that comparison cycle.
