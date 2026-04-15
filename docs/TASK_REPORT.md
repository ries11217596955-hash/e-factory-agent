## Summary
- Tightened executive decision output in `SITE_AUDITOR_AGENT` to enforce one-line `CORE PROBLEM`, a `P0` list capped at 3 items, and exactly 3 `DO NEXT` actions.
- Updated decision phrasing for hard-decision mode to remove soft/long wording and keep outputs immediately actionable.
- Added deterministic numbering for `P0` and `DO NEXT` in `11A_EXECUTIVE_SUMMARY.txt`.
- Kept scope limited to decision output shaping only; no pipeline/workflow/runtime flow changes.
- Preserved existing entrypoint and audit input contract.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Audit input unchanged: `reports/audit_result.json` (read-only input consumed by existing flow).
- Operator summary output unchanged path: `outbox/11A_EXECUTIVE_SUMMARY.txt`.

## Risks/blockers
- If incoming audit data does not trigger `P0` sources, fallback keeps one deterministic action in summary `P0` block.
- Hard slicing of `DO NEXT` assumes at least 3 static actions remain defined in this block.
