# TASK_REPORT

## Summary
- Added a universal `Normalize-ToArray` function to enforce deterministic array shape for potentially null/scalar/enumerable values.
- Applied DECISION_BUILD guard normalization at a single return-layer insertion point for `decision.problems`, `decision.next_actions`, `decision.inputs`, and `decision.product_closeout.{checks,evidence}`.
- Updated product closeout normalization to always coerce `checks` and `evidence` through the same universal array normalizer.
- Updated operator-output consumption paths to use normalized `problems` / `next_actions` collections and Count checks guarded via `Normalize-ToArray`.
- Preserved decision logic and structure intent; only collection-shape hardening was introduced.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- DECISION_BUILD shape guard is enforced in:
  - `Normalize-ToArray`
  - `Build-DecisionLayer` (pre-return normalization insertion)
  - `Normalize-ProductCloseout`

## Risks/blockers
- Runtime execution validation (e.g., generated `reports/RUN_REPORT.json`) was not performed in this environment because PowerShell runtime (`pwsh`) is unavailable.
- Validation performed here is static patch verification only.
