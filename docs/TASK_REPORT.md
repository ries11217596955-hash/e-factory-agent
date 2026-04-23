## Summary
- Root cause: after migrating uniqueness stores to `New-CaseInsensitiveKeyMap`, `Invoke-EvidenceReconciliation` in `agent.ps1` still used legacy HashSet-style calls (`.Add(value)` and `.Count`) on key-map objects, creating a mixed API contract in runtime reconciliation.
- Fixed key-map call sites in reconciliation by replacing legacy calls with helper API (`Add-KeyIfMissing`, `Get-KeyMapCount`) for `$issues` and `$actualUniquePageKeys`.
- Added explicit contract boundary documentation in `modules/runtime_safe.ps1` clarifying that key-map is not a HashSet and helper functions are the mandatory API surface.
- Performed a full sweep over SITE_AUDITOR_V2 runtime files (`agent.ps1`, `modules/runtime_safe.ps1`, `modules/stage_*.ps1`, `modules/report_*.ps1`, `modules/surface_context.ps1`) and verified zero remaining mixed API usages for key-map variables.
- No feature expansion, report redesign, or scope broadening was introduced.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - In `Invoke-EvidenceReconciliation`, replaced remaining legacy key-map operations:
    - `$issues.Add(...)` -> `Add-KeyIfMissing -Map $issues -Key ...`
    - `$actualUniquePageKeys.Add(...)` -> `Add-KeyIfMissing -Map $actualUniquePageKeys -Key ...`
    - `$issues.Count`/`$actualUniquePageKeys.Count` -> `Get-KeyMapCount -Map ...`
  - Result: reconciliation path is helper-only for migrated uniqueness structures.
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - Added explicit contract comments on `New-CaseInsensitiveKeyMap` to document/enforce API boundary:
    - key-map is normalized-key dictionary semantics, not HashSet semantics
    - callers must use helper API (`Add-KeyIfMissing`, `Test-KeyExists`, `Get-KeyMapKeys`, `Get-KeyMapCount`)

## Moved files/folders
- No files or folders were moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Runtime contract helpers remain in: `agents/site_auditor_v2/modules/runtime_safe.ps1`.
- Stage/report modules unchanged in structure and invocation paths under `agents/site_auditor_v2/modules/`.

## Risks/blockers
- Remaining mixed API risk: **NO** (runtime sweep completed; no detected key-map variable usages with `.Add(value)`, `.Contains(value)`, or direct `.Count` property semantics).
- Environment blocker: `pwsh` runtime execution is not available in this container, so live PowerShell execution validation could not be run here.
- Rollback instructions by file/block:
  1. Revert `agents/site_auditor_v2/agent.ps1` changes inside `Invoke-EvidenceReconciliation` (legacy helper migration block around issue collection, page-key accumulation, and status evaluation).
  2. Revert `agents/site_auditor_v2/modules/runtime_safe.ps1` contract comment block above `New-CaseInsensitiveKeyMap` if documentation boundary needs to be restored to previous text.

