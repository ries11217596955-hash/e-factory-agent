## Summary
Fixed `Resolve-MinimalDecision` validation in `lib/decision.ps1` to be shape-safe across PSCustomObject, hashtable/ordered dictionary, and JSON-derived objects. This resolves false `AUDIT_SUMMARY_INVALID: missing total property` failures when `total` is present but the runtime object is dictionary-shaped.

## Changed files
- agents/site_auditor_v2/lib/decision.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator (unchanged): `agents/site_auditor_v2/agent.ps1`
- Decision/report validation logic: `agents/site_auditor_v2/lib/decision.ps1` (`Resolve-MinimalDecision`)

## Root cause
- `Resolve-MinimalDecision` used direct property checks like `$Object.PSObject.Properties['key']`, which can fail for dictionary-shaped runtime objects (hashtable/ordered) even when the key exists.
- Result: valid JSON artifacts were flagged as invalid object shapes in-memory during REPORT_LAYER validation.

## Validation notes
- Added local helper functions:
  - `Test-ObjectHasKey` for key/property existence checks across dictionaries and PSObjects.
  - `Get-ObjectValueOrDefault` for safe value retrieval across shapes.
- Replaced shape-specific checks and reads for:
  - Required validations (`routes`, `total`, `status`).
  - Optional reads (`broken`, `first_screen_has_action`, limitations fields).
- Behavior preserved for negative cases:
  - Missing `total` still throws `AUDIT_SUMMARY_INVALID: missing total property.`
  - Missing `routes` still throws `ROUTES_SUMMARY_INVALID: missing routes property.`
  - Missing `status` still throws `LINK_SUMMARY_INVALID: missing status property.`

## Risks/blockers
- Could not execute the full SITE_AUDITOR_V2 workflow in this environment; validation was performed with focused local function invocations only.
- Change is intentionally minimal and scoped to decision validation in `lib/decision.ps1` (no module boundary or orchestrator expansion).
