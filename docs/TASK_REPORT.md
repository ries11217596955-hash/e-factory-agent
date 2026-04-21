## Summary
Normalized `OrderedDictionary` items inside `Convert-ToPageQualityObjectArray` so collection materialization now emits `[pscustomobject]` entries instead of raw ordered dictionaries in both foreach loops.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/page_quality.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Unchanged. No entrypoint or path changes were made.

## Risks/blockers
- Low risk: only item-type normalization was added in two existing foreach loops.
- If any caller depended on `OrderedDictionary` item typing specifically, those items are now `PSCustomObject` as requested.
