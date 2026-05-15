# AGENTS.md

## Purpose
Execution discipline for work inside `e-factory-agent`.

## Active AGENTOPS line
- Active build/test focus: `agents/site_auditor_v3/`
- Product target: universal audit engine
- Current website audits are an execution lane, not the whole product definition
- Current next universal product pack: `repair_execution_layer`

## Architecture law
- `run.ps1` = orchestrator only
- owner logic lives in `modules/`, `lib/`, `tools/`, and explicit contracts
- no blind refactor
- no hidden fallback that fabricates truth
- artifact/report truth outranks memory and speculation

## Operator run modes
The GitHub Actions operator surface is intentionally simple:
- `START`
- `NEXT`
- `FULL`

The operator chooses intent.
Session IDs, restore mechanics, batch state, and ledger transport remain internal.

## Current proven contour
SITE_AUDITOR_V3 already proves:
- long-run FULL orchestration
- bounded batch continuation
- session ledger continuity
- 100% session finalization
- final aggregate/operator/action outputs
- self-build truth alignment
- capability discovery selecting the next universal pack

Current next-pack truth:
- `repair_execution_layer`

## Output truth
A useful run must produce either:
- usable result; or
- explicit diagnostic output.

## Forbidden drift
- treating website fixture runs as the product boundary
- promoting target-specific findings into the universal product roadmap
- reviving legacy paths as active truth
- permanent tracked task-report clutter
- broad refactor under a cleanup label
- green-run claims without evidence
