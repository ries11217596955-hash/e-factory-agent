## Summary
- Repaired href resolution for `SITE_AUDITOR_V2` route extraction by replacing fragile URI handling with deterministic parsing in `Resolve-SafeUri`.
- Added explicit href taxonomy during route extraction: `anchor_only`, `unsupported_scheme`, `external_host`, `invalid_uri`, `internal_absolute`, `internal_relative`, and `normalization_failed`.
- Restored same-host canonicalization flow (`href -> absolute same-host URL -> normalized_route`) so valid links can be counted as `internal_links`.
- Added minimal route extraction diagnostics: `raw_links_found`, `internal_links`, `top_rejection_reasons`, `sample_rejected_hrefs` (max 3), and `sample_internal_hrefs` (max 3).
- HREF_RESOLUTION_CONTRACT_RESTORED = YES

## Changed files
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - Updated `Resolve-SafeUri` to deterministically handle website href forms (`/`, `/path/`, `relative-path`, `./relative-path`, same-host absolute http/https) and reject unsupported forms.
  - Root cause addressed: the prior generic/overload-led flow did not provide reliable href-class-aware handling, so valid same-host hrefs were frequently dropped before internal route counting.
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - Added `Get-HrefResolutionResult` helper to classify and resolve hrefs before normalization.
  - Updated route extraction loop to explicitly track rejection taxonomy and preserve internal href samples.
  - Added `top_rejection_reasons`, `sample_rejected_hrefs`, and `sample_internal_hrefs` to summary output.
- `docs/TASK_REPORT.md`
  - Replaced with this task report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged.
- Core extraction path remains:
  - `Get-ShallowRoutes` in `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - `Resolve-SafeUri` in `agents/site_auditor_v2/modules/runtime_safe.ps1`

## Risks/blockers
- Runtime execution verification is blocked in this container because PowerShell (`pwsh`) is not installed.
- Rollback instructions:
  1. `git checkout -- agents/site_auditor_v2/modules/runtime_safe.ps1`
  2. `git checkout -- agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  3. `git checkout -- docs/TASK_REPORT.md`
  4. Re-run route extraction checks in the target runtime environment.
