## Summary
Fixed SITE_AUDITOR_V2 report contract gate runtime failure by making `New-NormalizedFinding` tolerate an empty/null `MissingFields` list under PowerShell parameter binding rules.

## Changed files
- agents/site_auditor_v2/modules/report_contract.ps1
- docs/TASK_REPORT.md

## Root cause
`Normalize-FindingContract` creates an empty `System.Collections.Generic.List[string]` and passes it into `New-NormalizedFinding -MissingFields $missing`. `New-NormalizedFinding` declared `MissingFields` as `Mandatory = $true`; PowerShell treats an empty collection passed to a mandatory parameter as invalid and raises: `Cannot bind argument to parameter 'MissingFields' because it is an empty collection.`

## Fix
- `MissingFields` is no longer mandatory.
- `[AllowNull()]` and `[AllowEmptyCollection()]` were added.
- The function initializes a new `List[string]` internally when null is passed.

## Risks/blockers
- Runtime was not executed in this environment.
- Scope is intentionally limited to the exact binding defect; route, reconciliation, output writer, and report semantics were not changed.
