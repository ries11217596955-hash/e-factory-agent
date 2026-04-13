# TASK_REPORT

## Summary
- Applied a narrow fix only in the SITE_AUDITOR decision/output packaging boundary for `product_closeout` so downstream report generation no longer depends on unstable runtime shapes.
- Added `Normalize-ProductCloseout` to coerce `null`, singleton, enumerable, hashtable, and `PSCustomObject` inputs into one deterministic structure with safe defaults.
- Wired normalization at the producer and consumers of product closeout (`Build-DecisionLayer`, `Convert-ToProductStatus`, and `Write-OperatorOutputs`) so report/status generation remains stable.
- Added an explicit fallback `decision.product_closeout` object in the top-level failure path to ensure diagnostic artifacts remain human-readable even during run failure.
- Preserved source/live/page-quality logic and all capture/route normalization behavior.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Unchanged entrypoints:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- Could not run end-to-end PowerShell execution in this container if `pwsh`/`powershell` is unavailable.
- The patch intentionally does not refactor unrelated decision/report nodes; if a separate non-closeout `.Count` misuse exists elsewhere, it would require a separate targeted fix.
