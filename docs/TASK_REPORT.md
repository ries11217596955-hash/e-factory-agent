## Summary
- Unified route identity to canonical normalized path keys across route selection, findings, verdicts, and manifest reconciliation paths.
- Normalized route keys in `Get-VisualTargets` before deduplication/classification so selected routes always use canonical path-only identifiers.
- Added `source_url` alongside canonical `route` in `selected_routes`, preserving full URL separately while keeping route identity path-only.
- Post-processed `visual_manifest.json` page records to add canonical `route` and separate `source_url`, and rewrote `url` to normalized absolute URL for consistency.
- Canonicalized route keys used in findings/page verdict generation so one logical page maps to one route key across report sections.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v2/agent.ps1`.
- Route identity normalization is enforced during LINK-mode route selection and capture reconciliation in the same entrypoint.

## Risks/blockers
- Runtime execution against a live target was not performed in this environment, so validation is limited to static checks and script parse verification.
