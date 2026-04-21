## Summary
- Located the stable failing collection write in ROUTE_NORMALIZATION aggregate tracing within `Add-RouteNormalizationAggregateTrace`.
- Normalized the aggregate trace collection immediately before append to force array semantics (`@(...)`).
- Kept the repair to a single in-scope module and a single failing expression path.
- Avoided protected paths and made no entrypoint/workflow/decision/page_quality changes.
- Prepared this patch for PR-first review with minimal, deterministic impact.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/route_normalization_forensics.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Active repair path: `agents/gh_batch/site_auditor_cloud/modules/route_normalization_forensics.ps1` (`Add-RouteNormalizationAggregateTrace`).

## Risks/blockers
- End-to-end runtime validation is not executed here because PowerShell runtime invocation for full batch was not run in this patch step.
- If upstream code overwrites trace globals with non-array scalar values after this point, similar guards may be needed on adjacent append paths.
