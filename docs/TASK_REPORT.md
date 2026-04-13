## Summary
- Decoupled `product_status` fallback behavior in `Write-OperatorOutputs` from run-level `FinalStatus` blocking text.
- Added fallback reassignment so unresolved/blocked product status now derives from decision quality (`p0`/`problems`) instead of run status.
- Fallback now yields `NEEDS_FIX` when decision blockers/problems are present.
- Fallback now yields `SUCCESS` when no blockers/problems are present.
- Kept `FinalStatus` and decision structure untouched; only fallback assignment logic was changed.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry point unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Updated only `Write-OperatorOutputs` product status fallback assignment block.
- Audit layers and run status flow remain unchanged.

## Risks/blockers
- Validation in this task is static (code-path inspection); full behavioral confirmation requires pipeline execution where `FinalStatus=FAIL` and decision outputs are present.
