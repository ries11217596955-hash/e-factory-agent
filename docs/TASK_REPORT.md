## Summary
- Added a deterministic page-quality signal pack for LINK mode in `agents/site_auditor_v2/agent.ps1`, including per-route `status_code`, `html_length`, `title_present`, `internal_link_count`, `first_screen_text_present`, `screenshot_capture_ok`, `screenshot_count`, and candidate flags (`broken_candidate`, `thin_candidate`, `shell_like_candidate`).
- Implemented bounded defect rules from observable evidence only:
  - `BROKEN_ROUTE` from non-200/fetch-fail routes.
  - `THIN_ROUTE` from low HTML + low internal links + weak first-screen text.
  - `SHELL_PAGE` only when shell-like structure and weak first-screen text are present **and** screenshots succeeded.
  - `CAPTURE_FAILURE` per selected route when capture is materially incomplete.
- Enriched `page_verdicts` with required structure: `route`, `classification`, `signals`, `defect_candidates`, `evidence_refs`, `confidence`.
- Updated finding/action/priority mapping and decision chain usage so new deterministic finding types flow into `findings`, `priority_summary`, `decision_summary`, `next_strongest_move`, `ACTION_SUMMARY`, and human report payloads without changing LINK discovery core or screenshot engine core.
- Applied honest-clean wording update for low-confidence clean outcomes: `No page-level defects were confirmed in the checked scope.`

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- LINK output artifacts remain under `agents/site_auditor_v2/output/<run_key>/` and deterministic mirrors under `agents/site_auditor_v2/`.
- Findings/action/report chain remains in the same entrypoint and output paths; only deterministic page-quality signal computation and mapping logic were strengthened.

## Risks/blockers
- `pwsh` is not available in this container, so runtime execution validation for `agent.ps1` could not be executed here.
- Heuristics are intentionally bounded and deterministic; threshold tuning may be needed on real sites if false positives/negatives appear.

Rollback instructions (by file/block):
1. Full file rollback:
   - `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
2. Block rollback in `agents/site_auditor_v2/agent.ps1`:
   - Remove `Get-PageSignalThresholds` and related per-route signal extraction block in `Get-ShallowRoutes`.
   - Restore legacy route classification block near routes summary generation (`broken/thin/ok` based only on status + html length).
   - Restore legacy findings/page-verdict synthesis block (without per-route `signals`, `defect_candidates`, and shell/capture route-level findings).
   - Restore previous clean reasoning text if needed.
3. Commit rollback:
   - `git revert <commit_sha>`
