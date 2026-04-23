## Summary
- Built STRONG SIGNALS PACK in `SITE_AUDITOR_V2` to keep only four high-impact defect signals in the findings pipeline: `BROKEN_ROUTE`, `PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, and `NO_ACTION_PATH`.
- Added strict evidence gating so findings are emitted only when explicit evidence exists, and each finding now carries `route`, `evidence_text`, `evidence_type`, and `evidence_ref`.
- Enforced HIGH-confidence-only defect emission and removed micro-cluster synthetic findings to avoid collapsing or diluting direct page evidence.
- Hardened prioritization and sorting so `BROKEN_ROUTE` and entry/decision-surface `PROCESS_FIRST` issues are ranked first and feed `decision_summary` deterministically.
- Sharpened HUMAN_REPORT outputs to emphasize only the 1–2 strongest findings with concrete evidence snippets.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Updated priority and finding-rank mappings to include `BROKEN_ROUTE` as top severity.
  - Reworked findings synthesis to emit only strong-signal findings with explicit evidence fields.
  - Added strict `BROKEN_ROUTE` detection (`non-200` / failure) with status-backed evidence.
  - Removed MICRO_CLUSTER generation from defect findings to prevent aggregation-based dilution.
  - Updated decision and human-report wording to prioritize strongest evidenced finding and include evidence snippets.
  - Updated limitation evidence fields for structural consistency.
- `docs/TASK_REPORT.md`
  - Replaced report content for PACK 2 implementation.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Route discovery unchanged.
- Screenshot engine unchanged (`agents/site_auditor_v2/tools/capture_visuals.mjs` untouched).
- Ownership logic unchanged (`Get-OwnershipMode` and ownership action selection preserved).
- Confidence framework unchanged globally; PACK 2 only gates findings to HIGH-confidence evidence-backed signals.

## Risks/blockers
- `PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, and `NO_ACTION_PATH` now require first-screen text evidence; pages with sparse/empty extractable text may produce fewer findings despite visible issues.
- `BROKEN_ROUTE` now ranks highest and can dominate decision output when non-200 responses exist.
- Existing consumers that relied on MICRO_CLUSTER findings will no longer receive that synthetic issue type.
- No blockers encountered.

### Signal definitions
- `BROKEN_ROUTE`: route fails or returns non-200 status.
- `PROCESS_FIRST`: first screen starts with process/instructions before value statement.
- `NO_VALUE_FIRST_SCREEN`: first screen does not clearly communicate page value.
- `NO_ACTION_PATH`: first screen lacks a clear visible next step.

### Confidence rules
- Signal confidence is `HIGH` only when:
  - condition is true for the signal, and
  - required evidence is present (`status` evidence for `BROKEN_ROUTE`, `text` evidence for first-screen signals).
- Only `HIGH` confidence signals are promoted to defect findings.
- Lower-confidence signals are discarded from the defect findings list.

### Evidence rules
- Every emitted finding includes:
  - `route`
  - `evidence_text`
  - `evidence_type`
  - `evidence_ref`
- For first-screen signals, evidence is text snippet (first 1–2 lines).
- For broken routes, evidence is status-based text (`HTTP status code: ...`).
- Findings without required evidence are not emitted.

### Rollback
1. Revert `agents/site_auditor_v2/agent.ps1` signal maps (`Get-DefectPriorityByIssueType`, `Get-FindingTypeSortRank`) to remove `BROKEN_ROUTE` and previous rank ordering.
2. Revert findings synthesis block to prior signal conditions/evidence logic and remove `evidence_type`/`evidence_ref` fields.
3. Restore MICRO_CLUSTER generation block if aggregate synthetic findings are required again.
4. Revert decision reasoning/report wording updates tied to `BROKEN_ROUTE` and evidence-snippet output.
5. Restore previous `docs/TASK_REPORT.md` content if PACK 2 report is rolled back.
