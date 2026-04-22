## Summary
Added a strict post-capture evidence reconciliation layer in LINK mode that cross-checks `screenshots/*.png`, `visual_manifest.json`, and `RUN_REPORT.json`, writes an `evidence_reconciliation` block into the run report, and enforces capture-status downgrade/override when evidence is inconsistent.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Visual capture runtime entrypoint: `agents/site_auditor_v2/tools/capture_visuals.mjs`
- Deterministic outputs retained:
  - `agents/site_auditor_v2/RUN_REPORT.json`
  - `agents/site_auditor_v2/visual_manifest.json`
  - `agents/site_auditor_v2/screenshots/*.png`
- Run-scoped outputs retained:
  - `agents/site_auditor_v2/output/<run_id>/RUN_REPORT.json`
  - `agents/site_auditor_v2/output/<run_id>/visual_manifest.json`
  - `agents/site_auditor_v2/output/<run_id>/screenshots/*.png`

## Risks/blockers
- Reconciliation depends on manifest `captures[].file` conventions and screenshot naming (`page-XX-...`); manual file edits or naming drift will mark mismatches and can force PARTIAL/FAIL.
- If reconciliation itself throws, the run is now hard-failed with `decision_disabled = true` and diagnostic notes in `RUN_REPORT.json`.
