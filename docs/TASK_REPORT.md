## Summary
- Removed the PS5.1 runtime crash root cause by eliminating comparer-based generic set construction from runtime-critical paths and replacing uniqueness with a centralized case-insensitive key-map contract.
- Added and enforced a local PS5.1 runtime contract in the SITE_AUDITOR_V2 line (`agent.ps1` header + `modules/RUNTIME_CONTRACT.md`).
- Extracted early execution logic from `agent.ps1` into stage modules: link fetch/route extraction, route key selection, and capture reconciliation prep.
- Hardened phase truth by tracking granular stage boundaries (`ENTRY`, `LINK_FETCH`, `ROUTE_EXTRACTION`, `ROUTE_SELECTION`, `CAPTURE`, `RECONCILIATION`, `SURFACE_CONTEXT`, `REPORT_LAYER`).
- Failure diagnostics now persist stage progress metadata in both `RUN_REPORT.json` (via report fields) and `failure_summary.json` payload fields.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added PS5.1 runtime contract header comment.
  - Switched to stage-module imports (`stage_link_fetch.ps1`, `stage_route_keys.ps1`, `stage_capture_reconciliation.ps1`).
  - Removed inlined early-stage helper functions and delegated to modules.
  - Replaced runtime uniqueness usage with key-map helpers (no comparer HashSet constructors).
  - Added granular stage progression variables and failure metadata fields (`last_completed_stage`, `current_failure_stage`).
  - Replaced inlined capture/manifest reconciliation prep block with `Invoke-CaptureReconciliationPrepStage`.
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - Replaced unsafe set factory pattern with PS5.1-safe uniqueness helpers:
    - `New-CaseInsensitiveKeyMap`
    - `Add-KeyIfMissing`
    - `Test-KeyExists`
    - `Get-KeyMapKeys`
    - `Get-KeyMapCount`
  - Kept safe constructors for list/UTF8/URI helpers.
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - New stage module containing canonical URL normalization, response extraction, link fetch, route extraction/normalization.
  - Uses key-map uniqueness contract for route/filter dedupe.
- `agents/site_auditor_v2/modules/stage_route_keys.ps1`
  - New stage module containing canonical route-key normalization, route classification, and target selection.
  - Uses key-map uniqueness contract for selection dedupe.
- `agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1`
  - New stage module containing capture summary + reconciliation prep computations (selected/manifest key normalization + mismatch/fail-type aggregation).
- `agents/site_auditor_v2/modules/RUNTIME_CONTRACT.md`
  - New local runtime contract file documenting PS5.1 compatibility and safe uniqueness construction rules.

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Runtime-safe primitives: `agents/site_auditor_v2/modules/runtime_safe.ps1`.
- Stage boundaries and modules:
  - `LINK_FETCH` + `ROUTE_EXTRACTION`: `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - `ROUTE_SELECTION`: `agents/site_auditor_v2/modules/stage_route_keys.ps1`
  - `CAPTURE` prep + `RECONCILIATION` prep data: `agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1`
  - `SURFACE_CONTEXT` and `REPORT_LAYER` remain orchestrated in `agent.ps1`.
- Artifact behavior kept: run still writes `RUN_REPORT.json`, `failure_summary.json`, and existing LINK artifacts.

## Risks/blockers
- `pwsh` is not available in this container, so parser/runtime execution checks under PowerShell could not be executed locally.
- Changes are scoped to allowed paths only and do not add audit capabilities.
- Rollback instructions (file/block level):
  1. Revert commit to restore previous inline helper/stage logic in `agents/site_auditor_v2/agent.ps1`.
  2. Remove newly introduced stage modules:
     - `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
     - `agents/site_auditor_v2/modules/stage_route_keys.ps1`
     - `agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1`
  3. Restore prior runtime uniqueness implementation by reverting `agents/site_auditor_v2/modules/runtime_safe.ps1`.
  4. Remove runtime contract doc `agents/site_auditor_v2/modules/RUNTIME_CONTRACT.md` if contract location must be reverted.

## RUNTIME FACTORY RISK REMAINING
- NO

## PS5.1 CONTRACT ENFORCED
- YES
