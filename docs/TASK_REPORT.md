## Summary
- Hardened screenshot runtime/capture policy in `capture.mjs` with deterministic top/mid/bottom capture, fixed viewport, stable waits, and issue-triggered screenshot evidence with full-page fallback.
- Added issue-bound visual evidence modeling into page-quality processing so high-severity issue classes carry screenshot evidence refs and missing evidence degrades page-quality status.
- Replaced decision synthesis with a rule-first deterministic stage resolver (`BROKEN|STRUCTURE|CONTENT|UX|CONVERSION|READY`) plus one-line core problem and split `DO NEXT` (`now` vs `after`).
- Locked output contract to required artifacts and added contract-gated PASS behavior, including `RUN_DIAGNOSTIC.{json,txt}` when required artifacts are missing.
- Updated SSOT shaping in `reports/audit_result.json` to include schema/runtime/decision/facts/artifacts/visual_coverage fields and moved required operator text artifacts to `outbox/`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/capture.mjs`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Live capture entry unchanged: `agents/gh_batch/site_auditor_cloud/capture.mjs`
- SSOT outputs remain:
  - `reports/audit_result.json`
  - `reports/RUN_REPORT.json`
- Required operator artifacts now enforced in `outbox/`:
  - `outbox/11A_EXECUTIVE_SUMMARY.txt`
  - `outbox/00_PRIORITY_ACTIONS.txt`
  - `outbox/01_TOP_ISSUES.txt`

## Risks/blockers
- PowerShell runtime syntax validation could not be executed locally because `pwsh` is unavailable in this environment.
- The decision layer was intentionally simplified to deterministic rules for this batch; downstream consumers relying on legacy rich diagnosis fields may require follow-up compatibility tuning.
- Contract lock now intentionally forces FAIL when required artifacts are missing; legacy flows that depended on optimistic PASS will no longer pass.
