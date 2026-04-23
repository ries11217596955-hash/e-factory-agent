## Summary
Hardened the `ROUTE_SELECTION` stage in `agent.ps1` by adding explicit input guards, array normalization, deterministic stage logging, pre-selection filtering/sorting safety checks, and controlled fail returns (`NO_ROUTES_AVAILABLE` / `EMPTY_ROUTE_SET`) to prevent crash on malformed route input.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`
- Modified scope is limited to the `ROUTE_SELECTION` block in the entrypoint stage flow.

## Risks/blockers
- The new early `return @{ status='FAIL'; reason='...' }` exits from within stage execution; downstream artifact-writing behavior should be validated in full runtime execution.
- Runtime verification of full stage traces (`ROUTE_SELECTION: START ... SELECTED_OK`) requires executing the audit pipeline with representative route payload variants.
