## Summary
Hardened LINK-mode screenshot validation in `agents/site_auditor_v2/tools/capture_visuals.mjs` by enforcing a stricter default minimum capture size (10000 bytes), preserving explicit failure statuses (`missing_capture`, `empty_capture`, `render_fail`), and guaranteeing each capture manifest record reports `segment`, `file`, `size_bytes`, `status`, and `error`.

## Changed files
- `agents/site_auditor_v2/tools/capture_visuals.mjs`
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
- Capture validation uses a minimum PNG size threshold (10000 bytes); very minimal pages may classify as `empty_capture` and force partial/fail outcomes even if capture technically executed.
- Sites with anti-automation controls may still cause `render_fail` or `missing_capture`; those failures are now surfaced explicitly in manifests and run report metrics.
