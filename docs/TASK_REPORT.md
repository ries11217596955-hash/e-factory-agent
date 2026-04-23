## Summary
- Fixed the `Get-ShallowRoutes` href filtering loop crash by removing unsafe URI-object construction in the loop path.
- Replaced href resolution with string-only absolute URL assembly and filtering for root-relative and http(s) links.
- Added host filtering and route extraction using regex/string replacement only (no `[uri]` conversion in the href loop).
- Preserved route/internal-link accounting flow so route selection can continue with internal links collected.
- Kept change minimal and scoped to runtime hot path plus this report.

## Changed files
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`
- Updated runtime path: `agents/site_auditor_v2/modules/stage_link_fetch.ps1` (`Get-ShallowRoutes` href loop)

## Risks/blockers
- Host regex match uses direct host interpolation; unusual host strings containing regex metacharacters could affect matching behavior.
- `pwsh` is not available in this container, so full runtime acceptance execution could not be run locally.
