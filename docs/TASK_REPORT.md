## Summary
- Implemented a single-source decision chain in `agents/site_auditor_v2/agent.ps1`: findings → priority → `decision_summary` → `next_strongest_move` → `ACTION_SUMMARY.json` → bilingual HTML reports.
- Expanded `decision_summary` to required deterministic fields: `issue_type`, `primary_issue`, `priority`, `recommended_action`, `reasoning`, `ownership_mode`, and `audit_confidence`.
- Rewired `next_strongest_move` to always and only mirror `decision_summary.recommended_action`.
- Rebuilt `ACTION_SUMMARY.json` generation so first action always equals `decision_summary.recommended_action`, stays non-empty, and keeps max 3 `{ action, why, priority }` entries.
- Added client-facing `HUMAN_REPORT_RU.html` and `HUMAN_REPORT_EN.html` generation with required section order, equivalent meaning, and no internal/debug JSON style.
- Added hard consistency-lock failures for decision/action/report mismatches and null critical decision fields.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Decision/report outputs in `agents/site_auditor_v2/output/<run_key>/` now include:
  - `RUN_REPORT.json` (machine SSOT)
  - `ACTION_SUMMARY.json`
  - `HUMAN_REPORT_RU.html`
  - `HUMAN_REPORT_EN.html`
- Deterministic mirrors in `agents/site_auditor_v2/` include:
  - `RUN_REPORT.json`
  - `ACTION_SUMMARY.json`
  - `HUMAN_REPORT_RU.html`
  - `HUMAN_REPORT_EN.html`

## Risks/blockers
- Environment in this container does not include PowerShell runtime (`pwsh`), so script-level execution validation could not be run here.
- HTML content is generated from deterministic report fields; if upstream integrations require old `HUMAN_REPORT.md`, they must switch to the two HTML artifacts.
- Consistency-lock throws are intentionally strict and can fail the run when outputs drift.

Rollback instructions (explicit by file/block):
1. File-level rollback:
   - `git checkout -- agents/site_auditor_v2/agent.ps1 docs/TASK_REPORT.md`
2. Block-level rollback in `agents/site_auditor_v2/agent.ps1`:
   - Remove helper blocks `Escape-HtmlText` and `New-ClientReportHtml`.
   - Restore output path variables from HTML (`HUMAN_REPORT_RU.html`/`HUMAN_REPORT_EN.html`) to prior single markdown report path.
   - Restore decision synthesis block near `decision_summary`/`next_strongest_move`/`ACTION_SUMMARY` generation to prior logic.
   - Restore fallback report generation block to prior single markdown fallback path.
3. Commit-level rollback:
   - `git revert <this_commit_sha>`
