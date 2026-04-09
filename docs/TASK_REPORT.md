## Summary
- Root cause (exact): `Invoke-ExecutionStage` returned `@($results)` where `$results` is a `System.Collections.Generic.List[object]`. That wrapped the list as a single array element instead of returning the collection items, so assembly input shape became `object[]` containing one `List` rather than mode-result hashtables.
- Secondary shape issue: screenshot artifact extraction previously relied on pipeline wrapping and implicit enumeration, which was vulnerable to list/array shape drift when manifest values were not flattened as expected.
- Fix applied: return direct collection objects from stage/manifest functions, and use explicit `foreach` loops to build artifact path arrays as `[string]` values.
- Added debug logging for both critical counts to make shape issues observable during runtime logs.
- Expected effect: assembly receives proper per-mode result objects, stage 2 proceeds, and screenshot artifacts remain present in final bundle status/report outputs.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Screenshot sources: `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/reports` and `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/outbox`.
- Bundle screenshot output root: `agents/gh_batch/site_auditor_cloud/audit_bundle/bundle_artifacts`.
- Status outputs: `agents/gh_batch/site_auditor_cloud/audit_bundle/master_summary.json` and `agents/gh_batch/site_auditor_cloud/audit_bundle/audit_bundle_summary.json`.

## Risks/blockers
- Remaining risk: if any external/undocumented caller depended on wrapped list return shape (`@($results)` semantics), it may observe different enumeration behavior after this fix.
- Remaining risk: writing stage still re-reads manifest from filesystem; if files change between assembly and writing, artifact counts could differ (now visible via `SCREENSHOT_MANIFEST_COUNT` logs).
- No active blocker in scoped file changes.

## Exact changed lines
- In `Invoke-ExecutionStage`:
  - before: `return @($results)`
  - after: `return $results`
  - added: `Add-ExecutionLog 'MODE_RESULTS_COUNT=$($results.Count)'`
- In `Get-RepoScreenshotManifest`:
  - return is direct list (`return $manifest`), and now logs `Add-ExecutionLog "SCREENSHOT_MANIFEST_COUNT=$($manifest.Count)"`.
- In assembly artifact extraction:
  - uses explicit accumulation loop:
    - `$repoArtifacts = @()`
    - `foreach ($item in $repoScreenshotManifest) { $repoArtifacts += [string]$item.relative_path }`
- In writing stage artifact assignment:
  - replaced pipeline extraction with explicit loop assigning `$Assembled.bundle_status.repo.artifacts`.

## Before/after return shape
- `Invoke-ExecutionStage`:
  - Before: `object[]` with one element (`List[object]`).
  - After: direct `List[object]` (enumerates as mode-result items where consumed).
- `Get-RepoScreenshotManifest`:
  - Before (problematic contract in prior behavior): wrapped array containing list object.
  - After: direct `List[object]` manifest entries.
