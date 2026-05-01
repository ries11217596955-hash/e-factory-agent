# SITE_AUDITOR_V2 Architecture

SITE_AUDITOR_V2 is the **Universal Audit Engine** execution lane.

## Orchestration boundary

- `agent.ps1` is the orchestrator only.
- Modules own bounded contracts.
- New behavior must be isolated in modules and not grow a giant runtime in `agent.ps1`.

## Execution layers

1. ENTRY
2. LINK_FETCH
3. ROUTE_EXTRACTION
4. ROUTE_SELECTION
5. CAPTURE
6. RECON
7. SURFACE_CONTEXT
8. REPORT_LAYER
9. OUTPUT

## Fail-output contract

- Fail-output is a dedicated module boundary (`lib/fail_output.ps1`).
- The fail-output layer must always emit a diagnostic artifact.
- `RUN_REPORT.json` is the truth file for the next decision.
- Fail-output must not depend on REPORT_LAYER object-shape success.
