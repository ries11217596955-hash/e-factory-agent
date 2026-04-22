## Summary
Implemented W2 LINK-mode visual evidence baseline for `agents/site_auditor_v2` by adding deterministic screenshot capture (top/mid/bottom), a machine-readable `visual_manifest.json`, honest capture-state reporting in `RUN_REPORT`, and workflow support to upload new visual artifacts.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/tools/capture_visuals.mjs`
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Visual capture runtime entrypoint: `agents/site_auditor_v2/tools/capture_visuals.mjs`
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml`
- New deterministic visual outputs at repo root when available:
  - `agents/site_auditor_v2/visual_manifest.json`
  - `agents/site_auditor_v2/screenshots/*.png`
- Run-scoped visual outputs:
  - `agents/site_auditor_v2/output/<run_id>/visual_manifest.json`
  - `agents/site_auditor_v2/output/<run_id>/screenshots/*.png`

## Risks/blockers
- Visual capture now depends on Playwright + Chromium runtime availability; workflow installs these explicitly, but local runs without Node/Playwright will report capture limits honestly.
- Target sites with strict bot defenses or heavy client rendering may produce partial capture status despite successful LINK fetches.
