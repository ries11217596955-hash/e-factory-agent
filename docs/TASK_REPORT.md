## Summary
Started Phase C for `SITE_AUDITOR` by adding page-quality classification v1 on top of the existing live audit capture. Extended `capture.mjs` with lightweight deterministic DOM/text signals, added route-level quality classification/rollups in `agent.ps1`, included `live.route_details` and quality rollup counters in `audit_result.json`, and surfaced concise quality summaries in operator outputs while preserving existing runtime PASS/FAIL behavior.

## Changed files
- `agents/gh_batch/site_auditor_cloud/capture.mjs`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Downstream outputs preserved:
  - `agents/gh_batch/site_auditor_cloud/reports/audit_result.json`
  - `agents/gh_batch/site_auditor_cloud/reports/HOW_TO_FIX.json`
  - `agents/gh_batch/site_auditor_cloud/reports/01_TOP_ISSUES.txt`
  - `agents/gh_batch/site_auditor_cloud/reports/11A_EXECUTIVE_SUMMARY.txt`
  - `agents/gh_batch/site_auditor_cloud/reports/run_manifest.json`
  - `agents/gh_batch/site_auditor_cloud/outbox/REPORT.txt`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.ok`
  - `agents/gh_batch/site_auditor_cloud/outbox/DONE.fail`

## Risks/blockers
- Page-quality classification is intentionally v1 heuristic-based (threshold + keyword checks) and may need tuning on noisy/edge-case pages.
- End-to-end validation for all three modes (`REPO`, `ZIP`, `URL`) depends on runtime inputs and external URL accessibility; local verification covered URL mode flow and script syntax checks.
