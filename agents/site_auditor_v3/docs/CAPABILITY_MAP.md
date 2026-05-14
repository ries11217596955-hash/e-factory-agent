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

## Still open product layer
The next major product layer is not basic orchestration.
It is a scalable session aggregation/finalization layer that can combine current and future reporting streams into one final audit outcome.

## Guard
This map is a current capability summary.
Runtime PASS/FAIL still belongs to artifacts and validator output.
