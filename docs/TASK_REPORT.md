## Summary
Implemented a minimal LINK-mode counter-alignment patch so page counting and reporting are strictly driven by `selected_routes` from `Get-VisualTargets`. Updated capture/report plumbing to keep selected route count, manifest page set, and RUN_REPORT counters in 1:1 alignment, and added deterministic failure behavior for counter inconsistencies.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent runtime entrypoint: `agents/site_auditor_v2/agent.ps1`
- Visual target source of truth: `Get-VisualTargets` output (`selected_routes`)
- Visual capture input path: `Invoke-VisualCapture -Pages` now sourced only from selected route URLs
- Counter alignment path: `capture_summary` + `capture_report` counters now anchored to selected routes and manifest processed/failed counts
- Consistency gate path: selected-route vs manifest mismatch check now flags `counter_mismatch` and forces failed execution with `counter_inconsistency`

## Risks/blockers
- Validation here is static/script-level only; no live external LINK-mode run was executed in this environment.
- Manifest page URL normalization depends on available per-page URL/source URL fields in `visual_manifest.json`; malformed/missing manifest page URLs will trigger mismatch failure by design.
