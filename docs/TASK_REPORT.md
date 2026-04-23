## Summary
- Completed a full PS5.1 constructor sweep for `SITE_AUDITOR_V2` runtime path (`agent.ps1` + modules in scope).
- Added a runtime-safe helper module and switched risky constructor sites to explicit PS5.1-safe wrappers.
- Replaced all `::new(...)` constructor usage in target scope (including `Uri`, `UriBuilder`, `HashSet` with comparer, and `UTF8Encoding`).
- Preserved existing audit semantics, failure-phase truthfulness, and report structure (no feature or section expansion).
- Remaining constructor risks: **NO**.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added runtime-safe helper module import.
  - Replaced risky constructor calls:
    - `[UriBuilder]::new(...)` → `Resolve-SafeUriBuilder -Source ...`
    - `[Uri]::new(base, rel)` → `Resolve-SafeUriJoin -BaseUri ... -RelativeOrAbsolute ...`
    - `[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)` → `New-SafeHashSet -TypeName 'string' -Comparer ([System.StringComparer]::OrdinalIgnoreCase)`
    - `[System.Text.UTF8Encoding]::new($false)` → `(New-SafeUtf8NoBom)`
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - Added PS5.1-safe wrappers:
    - `New-SafeList`
    - `New-SafeHashSet`
    - `New-SafeUtf8NoBom`
    - `Resolve-SafeUriBuilder`
    - `Resolve-SafeUriJoin`
- `agents/site_auditor_v2/modules/util_io.ps1`
  - Replaced UTF-8 no-BOM constructor with `New-SafeUtf8NoBom` wrapper.
- `docs/TASK_REPORT.md`
  - Updated with constructor risk inventory, replacements, and rollback notes.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Modules used in runtime path:
  - `agents/site_auditor_v2/modules/runtime_safe.ps1`
  - `agents/site_auditor_v2/modules/util_io.ps1`
  - `agents/site_auditor_v2/modules/util_json.ps1`
  - `agents/site_auditor_v2/modules/surface_context.ps1`
  - `agents/site_auditor_v2/modules/report_safe_helpers.ps1`
  - `agents/site_auditor_v2/modules/report_layer.ps1`
- Artifact contract unchanged, including `RUN_REPORT.json` output path/flow.

## Risks/blockers
- Runtime validation in this environment is static (no live target crawl), so full acceptance for `RUN_REPORT.json` regeneration must be confirmed in the intended PS5.1 host execution.
- No protected paths were touched.
- No audit semantics/report-schema expansion was introduced.
- Rollback instructions:
  1. Revert commit `fix(site_auditor_v2): complete ps5.1 compatibility sweep`.
  2. Or manually restore pre-patch constructor sites in:
     - `agents/site_auditor_v2/agent.ps1`
     - `agents/site_auditor_v2/modules/util_io.ps1`
     - remove `agents/site_auditor_v2/modules/runtime_safe.ps1` and its import.
