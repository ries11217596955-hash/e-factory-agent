# AGENTS.md

## Purpose
Execution discipline for work inside `e-factory-agent`.

## Active AGENTOPS line
- Active build/test focus: `agents/site_auditor_v3/`
- Product target: universal audit engine
- Current website audits are an execution lane, not the whole product definition

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
Session IDs, restore mechanics, batch state and ledger transport remain internal.

## Output truth
A useful run must produce either:
- usable result; or
- explicit diagnostic output.

Tlegacy paths as active truth
- permanent tracked task-report clutter
- broad refactor under a cleanup label
- green-run claims without evidence
