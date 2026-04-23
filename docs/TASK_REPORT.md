## Summary
- Hardened first-screen PROCESS_FIRST detection to require explicit process keywords (`steps`, `choose`, `how to use`, `follow`, etc.) and no prior strong value statement, then emit a bounded first 1–2 line evidence snippet for traceability.
- Tightened value-presence logic so `first_screen_has_value` is true only for clear “what this page does/gives” language; weaker marketing/value hints are tracked separately as weak value.
- Added per-signal confidence (`HIGH`/`MEDIUM`/`LOW`) for intent/value/action/process signals and wired PROCESS_FIRST to become `HIGH` only when both hard conditions are strongly met.
- Updated findings synthesis to create DEFECT findings only for HIGH-confidence intent/process/action signals; medium/low signal states are preserved as route observations instead of defects.
- Kept report output strict: HUMAN_REPORT action focus and finding count now reflect only HIGH-confidence defect issues, reducing inflated/weak conclusions.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Scope respected: only `agents/site_auditor_v2/*` target logic and `docs/TASK_REPORT.md` reporting were changed.
- Output flow unchanged: findings/observations continue through `RUN_REPORT.json`, `ACTION_SUMMARY.json`, and `HUMAN_REPORT_{RU,EN}.html`.

## Risks/blockers
- Runtime validation in this container is limited because `pwsh` is not installed, so script execution was not performed here.
- Signal hardening remains regex/heuristic based; unusual copywriting patterns may still require future tuning.
- Rollback options:
  1. Full rollback: `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
  2. Commit rollback: `git revert <commit_sha>`
  3. Targeted rollback blocks in `agent.ps1`: first-screen pattern/confidence block, signal-to-finding confidence gates, and HUMAN_REPORT high-confidence filtering changes.
