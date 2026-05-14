# TASK_REPORT

## Summary
Implemented the **SESSION AGGREGATION & FINALIZATION LAYER v1.0** build-pack for Site Auditor V3.

This pack upgrades the current long-run audit contour from:

`START -> NEXT/FULL -> READY_FOR_FINAL`

to:

`START -> NEXT/FULL -> automatic session aggregation -> FINALIZED -> final operator handoff`

The implementation is intentionally **not** a narrow `FINAL_SUMMARY` file. It introduces a reusable aggregation/finalization layer designed to remain valid as future reporting streams appear.

## Decision locked in this pack
- `FINAL_SUMMARY` is **not** an operator/request `audit_action` anymore.
- It remains only as an **internal ledger marker** meaning “coverage is complete and the automatic finalizer must run.”
- Completed sessions are finalized automatically through the runtime/workflow path.

## New architecture introduced
### 1. Stream-aware session aggregation
New aggregation owner:
- `agents/site_auditor_v3/lib/session_finalization.ps1`

It builds a final session model from cumulative ledger truth, not from only the last batch.

Currently supported aggregation streams:
- `coverage_truth`
- `cumulative_findings`
- `remediation_actions`
- `batch_execution_history`

Future reporting streams are supported through a disclosure mechanism:
- ledger key: `future_report_streams`
- unknown/unregistered streams are surfaced as `COMPLETE_WITH_UNAGGREGATED_FUTURE_STREAMS` instead of being silently ignored.

### 2. Formal aggregation contract
New contract:
- `agents/site_auditor_v3/contracts/session_aggregation_contract.json`

It defines:
- finalization gate;
- supported streams;
- required final artifacts;
- future-stream policy;
- terminal session state and next action.

### 3. Finalization executor
New runtime tool:
- `agents/site_auditor_v3/tools/finalize_session.ps1`

Responsibilities:
- execute only when the session is fully covered and allowed to finalize;
- generate final outputs;
- update ledger, `RUN_REPORT`, and session summary;
- transition session truth to `FINALIZED`;
- become idempotent on repeated execution.

### 4. Final artifacts produced
When finalization succeeds, the run output now includes:
- `SESSION_AGGREGATE.json`
- `FINAL_OPERATOR_REPORT.md`
- `FINAL_ACTION_PLAN.json`
- `FINAL_FINDINGS_INDEX.json`

These are structured outputs, not decorative summaries:
- aggregate machine truth;
- operator-facing report;
- prioritized action plan;
- indexed finding/action clusters.

## Runtime integration completed
### Direct runtime
- `agents/site_auditor_v3/run.ps1`
  - invokes the finalizer after output generation when a run reaches finalization gate.

### Wrapper/runtime validation path
- `agents/site_auditor_v3/tests/run_and_validate.sh`
  - runs finalizer automatically;
  - runs `validate_session_finalization.py`;
  - includes final artifacts in wrapper manifest when present.

### FULL hosted loop
- `agents/site_auditor_v3/tools/workflow_full_loop.py`
  - finalizes the completed session automatically;
  - refuses to declare FULL complete unless finalization becomes `FINALIZED`.

### GitHub session-state publication
- `agents/site_auditor_v3/tools/workflow_session_state.py`
  - publishes `FINALIZED` state when finalization artifacts exist;
  - preserves open-session restore semantics;
  - blocks NEXT against already completed/finalized sessions.

## Artifact / packaging integration
### Unified hosted artifact
- `.github/workflows/site-auditor-v3.yml`
  - final manifest refresh now conditionally requires final artifacts when `finalization_status=FINALIZED`;
  - packaging truth records finalization status;
  - uploaded artifact remains self-describing.

### Output contract
- `agents/site_auditor_v3/contracts/output_contract.json`
  - upgraded to declare finalized-session outputs as conditional required artifacts;
  - removes the old blanket block against run-root markdown that would conflict with `FINAL_OPERATOR_REPORT.md`.

## Operator visibility
### AGENT_MAP / capability surface
- `agents/site_auditor_v3/lib/agent_map_builder.ps1`
  - exposes the new finalization capability and artifact links;
  - marks it as **implemented pending runtime proof** until a real run validates it.

### Capability map documentation
- `agents/site_auditor_v3/docs/CAPABILITY_MAP.md`
  - now reflects the long-run audit + finalization contour;
  - documents completed-session read order and future-stream policy.

## Manual FINAL_SUMMARY cleanup
Removed manual request/action support from:
- `agents/site_auditor_v3/modules/01_input.ps1`
- `agents/site_auditor_v3/modules/03_selection.ps1`
- `agents/site_auditor_v3/modules/03_7_audit_selection.ps1`

Result:
- external/request `audit_action` accepts only `START` or `NEXT`;
- `FINAL_SUMMARY` can no longer create a fake empty operator-triggered batch;
- finalization is automatic and ledger-driven.

## Validation added
New validator:
- `agents/site_auditor_v3/tests/validate_session_finalization.py`

It verifies, for completed sessions:
- finalization status is `FINALIZED`;
- all final artifacts exist;
- aggregate model has required stream IDs;
- coverage gate is `PASS` and pending count is `0`;
- final decision and one-next-action exist;
- operator report exposes required structural headings.

## Changed files
### New
- `agents/site_auditor_v3/lib/session_finalization.ps1`
- `agents/site_auditor_v3/contracts/session_aggregation_contract.json`
- `agents/site_auditor_v3/tools/finalize_session.ps1`
- `agents/site_auditor_v3/tests/validate_session_finalization.py`

### Updated
- `agents/site_auditor_v3/run.ps1`
- `agents/site_auditor_v3/tests/run_and_validate.sh`
- `agents/site_auditor_v3/tools/workflow_full_loop.py`
- `agents/site_auditor_v3/tools/workflow_session_state.py`
- `.github/workflows/site-auditor-v3.yml`
- `agents/site_auditor_v3/contracts/output_contract.json`
- `agents/site_auditor_v3/lib/agent_map_builder.ps1`
- `agents/site_auditor_v3/docs/CAPABILITY_MAP.md`
- `agents/site_auditor_v3/modules/01_input.ps1`
- `agents/site_auditor_v3/modules/03_selection.ps1`
- `agents/site_auditor_v3/modules/03_7_audit_selection.ps1`
- `agents/site_auditor_v3/modules/07_output.ps1`
- `docs/TASK_REPORT.md`

## Current entrypoints / paths
- Runtime entrypoint: `agents/site_auditor_v3/run.ps1`
- Wrapper validation entrypoint: `agents/site_auditor_v3/tests/run_and_validate.sh`
- FULL workflow loop: `agents/site_auditor_v3/tools/workflow_full_loop.py`
- Session-state publisher: `agents/site_auditor_v3/tools/workflow_session_state.py`
- Finalizer: `agents/site_auditor_v3/tools/finalize_session.ps1`
- Session ledger: `agents/site_auditor_v3/runs/sessions/<session_id>/AUDIT_SESSION_LEDGER.json`

## Risks / proof still required
This branch is **implemented**, but not yet accepted as operationally proven.

Required runtime proof after PR review:
1. Run hosted `FULL` on the live URL.
2. Confirm session reaches `FINALIZED`.
3. Confirm the unified artifact contains:
   - `SESSION_AGGREGATE.json`
   - `FINAL_OPERATOR_REPORT.md`
   - `FINAL_ACTION_PLAN.json`
   - `FINAL_FINDINGS_INDEX.json`
4. Confirm:
   - `RUN_REPORT.finalization.status = FINALIZED`
   - `SESSION_STATE.status = FINALIZED`
   - `ARTIFACT_MANIFEST.finalization_status = FINALIZED`
   - `missing_expected_files = []`
5. Confirm `validate_session_finalization.py` passes in the runtime lane.

Until that proof is produced, this capability remains **IMPLEMENTED_PENDING_RUNTIME_PROOF**, not declared fully active.
