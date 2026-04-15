## Summary
- Implemented a minimal decision engine in `agents/gh_batch/site_auditor_cloud/agent.ps1` that selects `site_stage`, `core_problem`, `p0`, and `do_next` from existing audit fields.
- Replaced prior static operator summary output generation with deterministic decision-based executive summary writing.
- Kept changes limited to the decision layer only; no detector expansion and no pipeline changes.
- Kept `audit_result.json` consumption unchanged (read-only source of existing fields).
- Enforced summary contract containing STAGE, CORE PROBLEM, P0 (max 3), and DO NEXT (3 steps).

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Audit source unchanged: `agents/gh_batch/site_auditor_cloud/reports/audit_result.json` (read-only input).
- Operator output updated at:
  - `agents/gh_batch/site_auditor_cloud/outbox/11A_EXECUTIVE_SUMMARY.txt`

## Risks/blockers
- If `reports/audit_result.json` is missing or malformed, decision summary generation in this block will not execute.
- `P0` can be empty when no trigger conditions are met (by design of the provided minimal rules).
