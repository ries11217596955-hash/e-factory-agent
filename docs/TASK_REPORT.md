## Summary
Repaired the SITE_AUDITOR cloud runtime to restore a stable artifact contract for GitHub Actions by implementing explicit mode resolution, guaranteed outbox/reports outputs, real mode-specific data collection, and honest PASS/FAIL signaling.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run.ps1`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/capture.mjs`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Runtime entrypoint: `agents/gh_batch/site_auditor_cloud/run.ps1`
- Main orchestration: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- URL capture worker: `agents/gh_batch/site_auditor_cloud/capture.mjs`
- Guaranteed output directories:
  - `agents/gh_batch/site_auditor_cloud/outbox/`
  - `agents/gh_batch/site_auditor_cloud/reports/`
- Guaranteed minimum outputs:
  - `outbox/REPORT.txt`
  - `outbox/DONE.ok` or `outbox/DONE.fail`
  - `reports/run_manifest.json`
  - `reports/audit_result.json`
  - `reports/HOW_TO_FIX.json`
  - `reports/00_PRIORITY_ACTIONS.txt`
  - `reports/01_TOP_ISSUES.txt`
  - `reports/11A_EXECUTIVE_SUMMARY.txt`

## Risks/blockers
- URL mode requires Node.js + Playwright runtime availability in the execution environment.
- URL mode quality depends on target site reachability and route responsiveness.
- ZIP mode currently validates payload presence only; extraction/deep analysis is still a downstream enhancement area.
