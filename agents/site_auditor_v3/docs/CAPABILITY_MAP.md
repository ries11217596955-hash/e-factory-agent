# CAPABILITY_MAP

## Active capability contour

### 1. Registry-driven runtime
- `run.ps1` executes the module registry as the runtime SSOT.
- Modules own business logic; the entrypoint coordinates only.

### 2. Long-run audit orchestration
- Operator modes: `START`, `NEXT`, `FULL`.
- Session ledger: `runs/sessions/<session_id>/AUDIT_SESSION_LEDGER.json`.
- Bounded batch auditing: inventory first, then audit in batches of up to 250 routes.
- Hosted session restore from unified GitHub artifact.

### 3. Inventory / route truth
- Route discovery inventory feeds both report truth and session ledger truth.
- Output must not re-crawl live routes during report composition.
- Coverage parity is enforced as session truth, not inferred from a later crawl.

### 4. Unified report artifact
- One hosted artifact contains:
  - `RUN_REPORT.json`
  - `TASK.json`
  - `AGENT_MAP.json`
  - `AGENT_MAP.md`
  - `ARTIFACT_MANIFEST.json`
  - `SESSION_STATE.json`
  - `LATEST_RUN_REPORT.json`
  - `sessions/<session_id>/AUDIT_SESSION_LEDGER.json`
- The manifest and `RUN_REPORT.packaging` must reflect the actual uploaded payload.

### 5. Session aggregation and finalization
- Completed audit sessions are not left at a placeholder `FINAL_SUMMARY` state.
- Finalization builds a stream-aware aggregation layer over the completed ledger.
- Contract source: `contracts/session_aggregation_contract.json`.
- Runtime owner: `tools/finalize_session.ps1` + `lib/session_finalization.ps1`.

Finalized-session outputs:
- `SESSION_AGGREGATE.json`
- `FINAL_OPERATOR_REPORT.md`
- `FINAL_ACTION_PLAN.json`
- `FINAL_FINDINGS_INDEX.json`

Finalization behavior:
- allowed only when pending inventory = 0;
- blocked when terminal batch failed;
- session state transitions to `FINALIZED`;
- next operator action becomes `REVIEW_FINAL_OPERATOR_REPORT`;
- aggregation discloses future declared streams that do not yet have registered aggregators.

### 6. Future stream compatibility
The aggregation layer treats reporting growth as streams, not ad hoc reports.
Currently supported streams:
- coverage truth;
- cumulative findings;
- remediation actions;
- batch execution history.

Future reporting streams must plug into the same aggregation contract instead of creating isolated final-summary surfaces.

## Current operator truth files
Read in this order for a completed hosted run:
1. `RUN_REPORT.json`
2. `SESSION_AGGREGATE.json`
3. `FINAL_OPERATOR_REPORT.md`
4. `FINAL_ACTION_PLAN.json`
5. `FINAL_FINDINGS_INDEX.json`
6. `AGENT_MAP.json`
7. `ARTIFACT_MANIFEST.json`

## Still missing after this layer
- New analytical stream families beyond the current session streams.
- Repair execution layer driven by `FINAL_ACTION_PLAN.json`.
- Cross-session trend / comparison layer.
- Benchmark layer.

## Structural guard
Do not regress to:
- one-off `FINAL_SUMMARY` shortcut files;
- final verdicts built from only the last batch;
- artifact self-description that diverges from the uploaded payload;
- future reports that bypass the session aggregation contract.
