## Summary
- Hardened URI normalization/join code paths by removing ambiguous `UriBuilder`/`Uri` constructor wrappers from `runtime_safe.ps1` and replacing usage with deterministic `System.Uri::TryCreate` + explicit URI string assembly helpers.
- Updated early runtime modules (`stage_link_fetch.ps1`, `stage_route_keys.ps1`) and early agent route rewrite path to use `Resolve-SafeUri` and `Get-NormalizedAbsoluteUriString` instead of removed wrapper factories.
- Added minimal bootstrap stage traces (`STAGE: ENTRY`, `STAGE: LINK_FETCH`, `STAGE: ROUTE_EXTRACTION`, `STAGE: ROUTE_SELECTION`) via shared helper `Write-BootstrapStageTrace` so operators can see last reached stage even if artifacts are missing.
- Preserved and tightened failure truth metadata by ensuring failure payloads and `RUN_REPORT.json` consistently include `last_completed_stage` and `current_failure_stage` fields in failure state updates.
- Performed key-map API sweep in the required runtime/report files; no mixed HashSet-style usage remains for `New-CaseInsensitiveKeyMap` objects.

## Changed files
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - Removed risky URI factory wrappers:
    - `Resolve-SafeUriBuilder`
    - `Resolve-SafeUriJoin`
  - Added deterministic helpers:
    - `Resolve-SafeUri`
    - `Get-NormalizedAbsoluteUriString`
    - `ConvertTo-SafeAbsoluteUri` (safe absolute parser)
    - `Write-BootstrapStageTrace` (minimal stage marker output)
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - Replaced URI builder-based canonicalization with deterministic helper-based normalization.
  - Replaced all URI joins to `Resolve-SafeUri`.
- `agents/site_auditor_v2/modules/stage_route_keys.ps1`
  - Replaced base-root URI assembly and route URL joins with deterministic helper-based methods.
- `agents/site_auditor_v2/agent.ps1`
  - Added early-stage trace emissions through module helper for ENTRY/LINK_FETCH/ROUTE_EXTRACTION/ROUTE_SELECTION.
  - Replaced remaining early URI join call in manifest route rewrite to `Resolve-SafeUri`.
  - Ensured failure report object consistently carries `last_completed_stage` and `current_failure_stage` in failure update branch.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Early stage boundaries after cleanup:
  - `ENTRY` (input/mode canonical validation)
  - `LINK_FETCH` (`Get-LinkSignals`)
  - `ROUTE_EXTRACTION` (`Get-ShallowRoutes`)
  - `ROUTE_SELECTION` (`Get-VisualTargets`)
- Early-stage trace markers now emitted exactly once per early stage via `Write-BootstrapStageTrace`.

## Risks/blockers
- RISKY URI FACTORY REMAINING = NO
- MIXED KEY-MAP API REMAINING = NO
- Remaining early-runtime risk = NO (for this patch scope: startup URI constructor ambiguity + early-stage traceability + failure-stage truth metadata).
- Blocker: PowerShell runtime (`pwsh`/Windows PS 5.1) is not available in this Linux container, so execution-level verification cannot be run here.

Rollback instructions by file/block:
1. `agents/site_auditor_v2/modules/runtime_safe.ps1`
   - Revert helper block replacing removed factories (`Resolve-SafeUri`, `Get-NormalizedAbsoluteUriString`, `ConvertTo-SafeAbsoluteUri`, `Write-BootstrapStageTrace`) to prior implementation.
2. `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
   - Revert canonical base URL and normalized route construction blocks that now call `Get-NormalizedAbsoluteUriString`.
   - Revert link join call sites now calling `Resolve-SafeUri`.
3. `agents/site_auditor_v2/modules/stage_route_keys.ps1`
   - Revert base root URL build and route target URL join call sites now calling helper methods.
4. `agents/site_auditor_v2/agent.ps1`
   - Revert four stage trace call lines (`Write-BootstrapStageTrace -Stage ...`).
   - Revert failure report field assignment block (`last_completed_stage` / `current_failure_stage`) in the existing failure branch.
