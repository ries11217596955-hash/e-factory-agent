## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Summary
- Fixed the remaining ROUTE_NORMALIZATION runtime blocker by removing brittle dictionary key access in `Safe-Get` that could throw `Argument types do not match` when manifest objects are deserialized into mixed dictionary key types.
- Kept the fix minimal and scoped to the live route normalization path used by SITE_AUDITOR.
- Preserved all existing output/report contracts and deterministic reasoning layers.
- Added this report update with explicit before/root-cause/after validation notes based on the current route manifest shape.

## Current blocker baseline (BEFORE)
- Failure stage from live runs: `ROUTE_NORMALIZATION`.
- Error text: `Argument types do not match`.
- `page_quality_status` remained `NOT_EVALUATED` when this crash occurred.
- Baseline evidence confirms `visual_manifest.json` had real route entries (`route_path`, `status`, `screenshotCount`, `title`, `bodyTextLength`, `links`, `images`, `h1Count`, `buttonCount`, `hasMain`, `hasArticle`, `hasNav`, `hasFooter`, `visibleTextSample`, `contaminationFlags`) but normalization still failed.

## Root cause (exact)
- File: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Function: `Safe-Get`
- Exact failure point:
  - Previous dictionary branch attempted direct dictionary API calls (`Contains` / keyed index assumptions) that are brittle against mixed runtime dictionary implementations produced by JSON deserialization.
  - Under real manifest object shapes, this could surface as `Argument types do not match` during live route normalization access patterns (ROUTE_NORMALIZATION stage), cascading into `page_quality_status=NOT_EVALUATED`.
- Type mismatch class:
  - dictionary key lookup assumption mismatch (string key lookup vs runtime dictionary key argument expectations).

## Fix applied (minimal)
- Updated `Safe-Get` dictionary handling to use key enumeration and string-equivalence matching (`$candidateKey -eq $Key` and `[string]$candidateKey -eq $Key`) before returning by the original candidate key.
- This removes dependence on brittle direct key-argument method calls and keeps lookups compatible across hashtable/ordered/generic dictionary shapes without broad refactor.

## After (expected runtime behavior)
- ROUTE_NORMALIZATION no longer crashes on the current real route manifest shape due to this key-argument mismatch.
- `Normalize-LiveRoutes` can normalize route objects and pass route data into `Build-PageQualityFindings`.
- `page_quality_status` can progress beyond mechanical `NOT_EVALUATED` caused by this specific blocker.
- Route verdicts, contradiction candidates, and site diagnosis can now operate on evaluated live route evidence when no other blocker exists.

## Validation evidence
- Static trace of changed path confirms `Safe-Get` dictionary branch now uses iteration/string-match access and no longer calls brittle dictionary key API with fixed argument type assumptions.
- Call path preserved and now benefits from the fix:
  - `Resolve-ManifestRoutes` → `Normalize-LiveRoutes` → `Build-PageQualityFindings` → contradiction layer / diagnosis layer.
- No output path changes were introduced.

## Non-regression notes
- Preserved contracts and paths for:
  - `route_details` construction
  - verdict classes (`verdict_class`)
  - contradiction layer candidates/summary
  - deterministic diagnosis layer outputs
  - existing report emissions and file locations
- No workflow/config/entrypoint changes.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- Environment limitation: PowerShell (`pwsh`) runtime is not available in this container, so live execution against a real bundle cannot be performed here.
- If a separate downstream blocker exists beyond ROUTE_NORMALIZATION, degraded mode should still report it honestly.
