## Summary
- Applied a surgical ROUTE_NORMALIZATION boundary fix in `agents/gh_batch/site_auditor_cloud/agent.ps1` only.
- Added safe key normalization for dictionary-shaped route payloads before route field access.
- Updated route extraction to normalize dictionary keys to strings at the `routes` boundary.
- Kept diagnosis/contradiction/maturity/output layers unchanged.
- Validation run is blocked in this container because `pwsh` is unavailable.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- `agents/gh_batch/site_auditor_cloud/run.ps1`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- Environment blocker: PowerShell runtime (`pwsh`) is not installed in this container, so the required live validation run could not be executed here.
- Root-cause type evidence is derived from deterministic code-path inspection of ROUTE_NORMALIZATION helpers.

## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/README.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-update)

## ROOT_CAUSE
- **Function name:** `Safe-Get` (invoked from `Normalize-LiveRoutes` / `Resolve-ManifestRoutes` during ROUTE_NORMALIZATION).
- **Exact expression/operation:** key comparison at dictionary-access boundary: `if ($candidateKey -eq $Key)`.
- **Left operand type:** non-string dictionary key from manifest route object (e.g., nested/object key in `System.Collections.Hashtable` / `OrderedDictionary`).
- **Right operand type:** `[string]` key requested by accessor (e.g., `'route_path'`, `'status'`, `'url'`).
- **Sample values (short):** left=`@{path='/'; status=200}` (object key), right=`'route_path'`.
- **Why mismatch happens:** ROUTE_NORMALIZATION accepted heterogeneous dictionary payloads and attempted implicit typed comparison before key normalization, which can throw `Argument types do not match` for incompatible key/value shapes.

## FIX_APPLIED
- Added `Convert-ToStringKeyDictionarySafe` and invoked it at ROUTE_NORMALIZATION boundaries only:
  - on `explicitRoutes` in `Resolve-ManifestRoutes`
  - on each `$route` item in `Normalize-LiveRoutes`
- The helper performs safe normalization of dictionary keys to strings and preserves values.
- This is minimal because it changes only the failing boundary behavior (key-type normalization) and does not alter downstream audit layers or contracts.

## VALIDATION
- **Before (known state):** live evaluation fails at `failure_stage=ROUTE_NORMALIZATION` with `Argument types do not match`; page quality remains `NOT_EVALUATED`.
- **After (code-path expectation):** mixed/non-string dictionary keys are normalized to string-key dictionaries before field access, preventing the ROUTE_NORMALIZATION key comparison mismatch.
- **Execution evidence in this container:** full run not possible due to missing `pwsh`; therefore `REPORT.txt`/`audit_result.json` regeneration could not be confirmed locally.

## NEXT_BLOCKER_IF_ANY
- `NONE` identified from static inspection; runtime confirmation is blocked by missing PowerShell runtime in this environment.
