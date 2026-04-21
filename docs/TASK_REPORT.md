## Summary
- Stabilized screenshot collection shape in `Build-PageQualityFindings` before screenshot count fallback aggregation.
- Materialized both `$pq3RouteScreenshots` and `$pq3RouteIssueScreenshots` with local `@(...)` normalization immediately before count usage.
- Kept the existing guard condition logic intact and unchanged.
- Did not modify helpers, including `Convert-ToPageQualityObjectArray`, and did not refactor unrelated logic.
- Kept scope minimal to the requested module plus this task report update.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/page_quality.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Updated path: `agents/gh_batch/site_auditor_cloud/modules/page_quality.ps1` within `Build-PageQualityFindings` around screenshot fallback count normalization.

## Risks/blockers
- No blockers identified.
- Validation performed via targeted file inspection; runtime behavior still depends on live route payload shapes.
