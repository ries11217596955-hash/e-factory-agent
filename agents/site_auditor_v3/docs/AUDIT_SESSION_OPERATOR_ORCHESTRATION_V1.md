# AUDIT SESSION OPERATOR ORCHESTRATION v1.0

## Purpose
This contract defines the operator-facing execution model for `SITE_AUDITOR_V3` after session-ledger runtime continuity was proven.

The operator must choose **intent**, not manually manage ledger internals.

---

## Public operator menu

GitHub Actions should expose only:

1. `target_url`
2. `run_mode`
   - `START`
   - `NEXT`
   - `FULL`

No public UI fields for:
- `session_id`
- `batch_size`
- `auto_audit`
- fake or unproven scan-depth selectors

Internal defaults:
- `batch_size = 250`
- session continuation state is resolved by the agent/workflow, not the operator

---

## Mode contract

### START
Input:
- target URL
- run_mode = `START`

Behavior:
1. Resolve the target URL scope.
2. Check whether an unfinished session already exists for the same target scope.
3. If one exists, safe-stop with `OPEN_SESSION_ALREADY_EXISTS_FOR_URL`.
4. If none exists, create a new audit session.
5. Process one batch up to 250 pages.
6. Persist the updated session state.
7. Emit a cumulative report for the session state after this batch.
8. Stop.

### NEXT
Input:
- target URL
- run_mode = `NEXT`

Behavior:
1. Resolve the target URL scope.
2. Find unfinished audit sessions for that exact target scope.
3. If none exists, safe-stop with `NO_OPEN_SESSION_FOR_URL` and instruct the operator to run `START` first.
4. If more than one exists, safe-stop with `AMBIGUOUS_OPEN_SESSIONS_FOR_URL`.
5. If exactly one exists, resume it automatically.
6. Process exactly one next batch up to 250 pages.
7. Persist the updated session state.
8. Emit a cumulative report for the whole session, not only for the current batch.
9. Stop.

### FULL
Input:
- target URL
- run_mode = `FULL`

Behavior:
1. Resolve the target URL scope.
2. Find unfinished audit sessions for that exact target scope.
3. If none exists, create a fresh session and begin from the first batch.
4. If exactly one exists, resume that session from its current checkpoint.
5. If more than one exists, safe-stop with `AMBIGUOUS_OPEN_SESSIONS_FOR_URL`.
6. Continue batch-by-batch internally until the session is complete or a safe-stop/runtime failure occurs.
7. Persist session state after each batch.
8. Emit the final cumulative report for the whole session.

---

## Target-scope safety

Resume logic must never select “the latest session overall.”
It must select unfinished sessions only for the exact normalized target scope.

At minimum, a persisted session state must contain enough target identity to support safe matching:
- normalized target URL or target scope key
- base URL
- session ID
- completion state

Wrong-target continuation is forbidden.

---

## Safe-stop contract

Operator mistakes must produce a clean diagnostic result, not an ambiguous crash.

### Required safe-stop classes

- `NO_OPEN_SESSION_FOR_URL`
- `OPEN_SESSION_ALREADY_EXISTS_FOR_URL`
- `AMBIGUOUS_OPEN_SESSIONS_FOR_URL`
- `SESSION_ALREADY_COMPLETED`
- `SESSION_STATE_NOT_RESTORABLE`

A safe-stop report must provide:
- status = `STOP`
- error code
- target URL / scope key
- human-readable explanation
- one operator action

---

## Cumulative report contract

`NEXT` and `FULL` must not report only the current batch.
They must expose the session-level truth.

### Required report structure

#### `session_summary`
Cumulative across the whole session:
- session ID
- target scope
- batches completed
- total inventory count
- total audited count
- total pending count
- coverage percent
- aggregate finding counts
- session status
- next action

#### `current_batch_summary`
Only the batch executed in the current workflow run:
- batch ID
- audited count in this run
- findings in this run
- coverage delta when available

`RUN_REPORT.audit_session` can remain as the existing machine-facing block, but the operator-readable truth must be cumulative.

---

## GitHub Actions persistence model

GitHub Actions runners are ephemeral. Therefore `NEXT` and resumed `FULL` cannot rely on local filesystem continuity across workflow runs.

The workflow/orchestration layer must implement session-state restore and persist operations. The persistence mechanism may evolve, but the operator contract does not:

- `START` publishes resumable session state.
- `NEXT` restores the matching open session automatically.
- `FULL` either creates a new session or restores the matching open session, then continues until complete.

The session-state transport must be verifiable and safe-stop if the required state cannot be restored.

---

## Priority lock

When an audit session is still open:
- `RUN_REPORT.next_step`
- `RUN_REPORT.decision_action`

must prioritize continuing or finishing the audit session over capability expansion or unrelated meta-build actions.

This lock applies until the session is complete or stopped for repair.

---

## Non-goals of this contract

This document does not define:
- internal storage backend details beyond safe persistence/restore requirements
- future scan-depth product profiles
- multi-tenant session management
- user-facing UI outside GitHub Actions

---

## Implementation order

1. Clean GitHub Actions menu to `target_url + run_mode`.
2. Add internal request mapping from `run_mode` to runtime actions.
3. Add target-scoped session discovery / restore safety.
4. Add GitHub Actions persistence transport for session state.
5. Add `FULL` loop orchestration.
6. Add cumulative session report contract.
7. Validate safe-stop paths and happy paths.
