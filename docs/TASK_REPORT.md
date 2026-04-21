## Summary
- Normalized final route-level output collection shapes in `Build-PageQualityFindings` so route findings and route issues are always materialized as arrays at the output boundary.
- Enforced explicit final-stage normalization with `@(...)` for both `$routeFindings` and `$routeIssues` immediately before final output assignment.
- Kept earlier guard/count/fallback logic unchanged and avoided structural refactoring.
- Limited code changes to one requested module file.
- Updated this task report per PR-first process requirements.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/page_quality.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Updated path: `agents/gh_batch/site_auditor_cloud/modules/page_quality.ps1` (`Build-PageQualityFindings` final route output assembly stage).

## Risks/blockers
- No blockers identified.
- Low risk: change is constrained to output-shape normalization immediately before route output assignment.
