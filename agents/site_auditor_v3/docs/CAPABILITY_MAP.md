# CAPABILITY_MAP — SITE_AUDITOR_V3

## Current proven capabilities

### 1. Operator run modes
- GitHub Actions exposes:
  - `START`
  - `NEXT`
  - `FULL`

### 2. Session-ledger orchestration
- START creates a scoped audit session.
- NEXT restores the matching open session automatically.
- FULL starts or resumes a session and advances it until completion.

### 3. Unified artifact truth
One artifact carries:
- `RUN_REPORT.json`
- `AGENT_MAP.json`
- `AGENT_MAP.md`
- `TASK.json`
- `SESSION_STATE.json`
- session ledger truth
- artifact manifest / packaging truth

### 4. Inventory before batching
- route inventory is discovered before audit batching
- audit batches are capped separately from discovery scope
- current batch model = up to 250 pages per bounded pass

### 5. Inventory/report truth alignment
- `RUN_REPORT.route_discovery_result`
- session ledger inventory
- audit continuation state

must describe the same session truth.

### 6. Generated agent map
`AGENT_MAP` is generated from current runtime/contracts and exposes:
- module topology
- system capabilities
- runtime session snapshot

### 7. Session aggregation and finalization
Completed audit sessions now finalize automatically after 100% coverage.

Finalization layer produces:
- `SESSION_AGGREGATE.json`
- `FINAL_OPERATOR_REPORT.md`
- `FINAL_ACTION_PLAN.json`
- `FINAL_FINDINGS_INDEX.json`

Finalized session truth:
- `SESSION_STATE.status = FINALIZED`
- `RUN_REPORT.finalization.status = FINALIZED`
- next operator action = `REVIEW_FINAL_OPERATOR_REPORT`

Aggregation is stream-aware, not a one-off summary. Current streams:
- coverage truth
- cumulative findings
- remediation actions
- batch execution history

Future reporting streams must attach to the same aggregation model instead of creating isolated final-summary outputs.

## Still open product layer
The next major product layer is no longer basic orchestration or finalization.
It is the repair/execution layer that consumes `FINAL_ACTION_PLAN.json`, followed later by cross-session comparison and benchmark layers.

## Guard
This map is a current capability summary.
Runtime PASS/FAIL still belongs to artifacts and validator output.
