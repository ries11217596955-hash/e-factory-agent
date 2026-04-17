## Summary
Implemented a minimal PAGE_QUALITY_BUILD output stabilization path so product classification fields are always populated for operator contracts and run reports.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Updated fallback truth extraction in `Get-FallbackTruthEvidence` to always emit `product_status`, `product_reason`, and `product_actions` defaults.
- Updated `Write-RunForensicsReports` to enforce non-empty product status/reason/actions before composing RUN_REPORT contract evidence.
- Updated `Write-OperatorOutputs` to persist `product_actions` into `audit_result.json` from decision actions with deterministic fallback actions.
- Updated fallback RUN_REPORT contract assembly in `Ensure-OutputContract` to include `product_actions` in `key_evidence_excerpts`.
- No changes to `SOURCE_AUDIT` logic or `DECISION_BUILD` logic.

## Risks/blockers
- Low risk: deterministic fallback-only defaults; no stage control-flow rewrite.
- No blockers.
