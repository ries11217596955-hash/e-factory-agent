## Summary
- Root cause: PowerShell 5.1 runtime hit constructor binding failures on generic collection `::new(...)` paths inside `SITE_AUDITOR_V2`, which can raise `Cannot find an overload for "New"` before audit completion.
- Replaced `List[object]::new()` and `List[string]::new()` with `New-Object ...` constructors in the target scope (`agents/site_auditor_v2`), preserving existing audit/report behavior.
- Removed argument-based list constructor usage for `producedArtifacts` fail-path rebuild and replaced it with explicit list initialization + item append.
- Added a non-blocking PS5.1 trace guard near startup: emits `Running in PS5.1 compatibility mode` when `$PSVersionTable.PSVersion.Major -lt 6`.
- Added a null-safe array initialization for `actionSummaryActions` to avoid unsafe single-null array wrapping.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added PS5.1 compatibility trace guard.
  - Replaced generic list `::new()` constructors with `New-Object` for runtime compatibility.
  - Reworked fail-path `producedArtifacts` reconstruction to remove argument constructor usage.
  - Made `actionSummaryActions` array init null-safe.
- `agents/site_auditor_v2/modules/report_layer.ps1`
  - Replaced generic list `::new()` constructors with `New-Object`.
- `docs/TASK_REPORT.md`
  - Updated with this compatibility patch report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Target module path unchanged: `agents/site_auditor_v2/modules/report_layer.ps1`.
- Output artifacts/paths unchanged (including `RUN_REPORT.json` contract).

## Risks/blockers
- Validation in this environment is static-only (no full external target run), so runtime acceptance must be confirmed in pipeline/host PowerShell 5.1 execution.
- HashSet/Uri/Encoding constructor calls were intentionally left unchanged to avoid audit/report logic drift; this patch is scoped to requested list-constructor compatibility.
- Rollback instructions:
  1. Revert commit `fix(site_auditor_v2): replace ::new constructors for PS5.1 compatibility`.
  2. Or manually restore prior constructor forms in:
     - `agents/site_auditor_v2/agent.ps1`
     - `agents/site_auditor_v2/modules/report_layer.ps1`
  3. Remove PS5.1 trace guard block near top of `agent.ps1` if full rollback is required.
