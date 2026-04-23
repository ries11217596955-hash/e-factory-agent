## Summary
- Added an INTENT + VALUE audit layer in `agents/site_auditor_v2/agent.ps1` with deterministic page-type classification (`HOME`, `HUB`, `DECISION`, `TOOL`, `ARTICLE`, `UNKNOWN`) using URL/title/structure heuristics only.
- Extended first-screen analysis signals (text + top screenshot evidence reference) to compute `first_screen_has_value`, `first_screen_has_action`, `first_screen_is_process_like`, and `value_before_process` from bounded regex rules and first-screen extraction.
- Added route-level DEFECT findings `INTENT_FAIL`, `NO_ACTION_PATH`, and `PROCESS_FIRST` with explicit evidence attachment (`ROUTES_SUMMARY`, first-screen snippet pointer, and top screenshot file when available) and ownership-based action mapping.
- Integrated new findings into existing decision/action/report chain (`decision_summary`, `next_strongest_move`, `ACTION_SUMMARY`, `HUMAN_REPORT`) while preserving route discovery, screenshot engine, ownership logic, confidence logic, and report structure.
- Updated finding priority behavior so intent/value failures surface first when present, including P0 handling for `INTENT_FAIL` on HOME/DECISION and `NO_ACTION_PATH` on critical page types.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Allowed path scope respected: only `agents/site_auditor_v2/agent.ps1` and `docs/TASK_REPORT.md` were changed.
- Output/report flow unchanged: findings continue to feed `RUN_REPORT.json`, `ACTION_SUMMARY.json`, and `HUMAN_REPORT_{RU,EN}.html` via the existing LINK-mode pipeline.

## Risks/blockers
- Runtime execution validation is blocked in this container because `pwsh` is unavailable.
- First-screen intent/value detection is heuristic by design (no NLP/ML/LLM judgment); some edge pages may require pattern tuning.
- Rollback instructions:
  1. Full rollback: `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
  2. Commit rollback: `git revert <commit_sha>`
  3. Partial rollback target blocks in `agent.ps1`: page-type heuristic function, first-screen intent/value signal extraction block, and new finding synthesis blocks (`INTENT_FAIL`, `NO_ACTION_PATH`, `PROCESS_FIRST`).
