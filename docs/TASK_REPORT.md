## Summary
- Built a deterministic findings-to-action report layer for `SITE_AUDITOR_V2` LINK mode using only existing runtime truth artifacts (`ROUTES_SUMMARY`, `visual_manifest`, `capture_report`, selected routes, and run budget metadata).
- Standardized bounded finding classes to observable report-layer facts: `BROKEN_ROUTE`, `THIN_ROUTE`, `CAPTURE_FAILURE`, and `ROUTE_OVERFLOW_ONLY`.
- Made `ACTION_SUMMARY.json` always valid and non-empty by writing structured payloads in both normal and fallback paths, including clean/no-finding runs.
- Updated operator handoff/memory messaging to stop overclaiming deterministic findings when `findings=[]`, and aligned next-action guidance with actual run truth.
- Kept scope limited to report-layer mapping and handoff honesty; no crawl-depth expansion, screenshot engine changes, route-contract changes, or new capabilities.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report artifacts remain under: `agents/site_auditor_v2/output/<run_id>/`.
- Deterministic mirror artifacts remain under: `agents/site_auditor_v2/` (`RUN_REPORT.json`, `ACTION_SUMMARY.json`, etc.).

## Risks/blockers
- `ROUTE_OVERFLOW_ONLY` is intentionally a coverage-limit finding (not a page defect); operators must avoid treating it as content breakage.
- Findings are intentionally bounded to observable LINK artifacts only; no UX/conversion/monetization inference is performed.
- If execution fails before LINK analysis completes, fallback `ACTION_SUMMARY.json` is still valid but contains no actionable page-level findings by design.

## Rollback instructions
1. Revert commit for this task:
   - `git revert <commit_sha>`
2. Or restore prior file state directly:
   - `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
3. Re-run LINK mode to regenerate artifacts with prior report behavior.
