## Summary
- Normalized findings classification in `SITE_AUDITOR_V2` into `DEFECT` vs `LIMITATION` and added explicit `type` + `category` on each finding.
- Recomputed counting and priority outputs so only `DEFECT` findings drive `findings_count`, severity totals, and `priority_summary.top_issues`.
- Updated action and next-move logic so limitation-only runs produce coverage/budget expansion guidance instead of page-fix remediation.
- Updated operator handoff reasoning for limitation-only outcomes to explicitly state no page-level defects and sampling constraints.
- Updated run report schema to require `findings_count`, `limitation_count`, and finding-level `type`/`category`.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Findings/report contract remains: `agents/site_auditor_v2/contracts/run_report.schema.json`.
- Output artifacts remain under `agents/site_auditor_v2/output/<run_id>/` with deterministic mirrors in `agents/site_auditor_v2/`.

## Risks/blockers
- Existing consumers that assumed all findings are defects may need to read `category` and use `findings_count` vs `limitation_count` explicitly.
- `issue_type` is retained for compatibility, while `type` is now also required; downstream parsers should treat them as equivalent finding type identifiers.
- No runtime/crawler/route selection behavior changed; only findings-layer normalization and reporting semantics changed.

## Rollback instructions
1. Revert this task commit:
   - `git revert <commit_sha>`
2. Or restore modified files directly:
   - `git checkout -- agents/site_auditor_v2/agent.ps1 agents/site_auditor_v2/contracts/run_report.schema.json docs/TASK_REPORT.md`
3. Re-run `SITE_AUDITOR_V2` LINK mode to regenerate artifacts using prior semantics.
