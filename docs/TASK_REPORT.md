## Summary
Implemented deterministic LINK-mode route prioritization for visual capture input. Routes are now classified as ROOT, DECISION, CONTENT, or LOW_VALUE and selected by priority tiers with a hard max of 5 routes. Added hard exclusions for `/feed`, `/rss`, and pagination routes (`/page/<n>`), and propagated only selected routes to screenshot input plus RUN_REPORT metadata.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent runtime entrypoint: `agents/site_auditor_v2/agent.ps1`
- Route prioritization path: `Get-VisualTargets` (classification, tiering, sampling, hard exclusions)
- Screenshot input path: `Invoke-VisualCapture` call site now uses selected prioritized URLs only
- RUN_REPORT propagation path: `selected_routes` field reflects filtered route set sent to screenshot layer

## Risks/blockers
- Tier-1 routes are capped by `max_routes=5` to enforce processing limit; in edge cases with more than 5 tier-1 candidates, only the first deterministic subset is processed.
- `pwsh` runtime validation is not executable in this environment, so behavior was validated statically by code inspection only.
