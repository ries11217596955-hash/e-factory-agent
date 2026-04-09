## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)
- `docs/README.md`
- `docs/FINAL_ROOT_CLOSEOUT.md`

## Summary
- Upgraded `run_bundle.ps1` reporting layer to generate decision-grade operator summaries directly in the final bundle without changing execution flow, artifact contracts, or mode orchestration.
- Added operator-first synthesis that extracts existing evidence from copied REPO outputs (`repo/outbox/REPORT.txt`, `repo/reports/00_PRIORITY_ACTIONS.txt`, `repo/reports/01_TOP_ISSUES.txt`) and produces concise `CORE_PROBLEM`, `P0/P1/P2`, and `DO_NEXT` content.
- Ensured all required human-facing bundle files are present and updated on each run:
  - `audit_bundle/00_PRIORITY_ACTIONS.txt`
  - `audit_bundle/01_TOP_ISSUES.txt`
  - `audit_bundle/11A_EXECUTIVE_SUMMARY.txt`
- Implemented dedupe + cap behavior for priority groups (max 5 per group) and next actions (max 3), with concrete fallback actions when source sections are missing.
- Preserved partial-value behavior by surfacing available findings even when status is `PARTIAL`/`FAIL`, with explicit confidence statements instead of empty/zero-looking summaries.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- Bundle structure and artifact roots remain unchanged (`audit_bundle/`, `audit_bundle/repo/`, `audit_bundle/bundle_artifacts/`).
- No Playwright code, workflow files, checkout/binding logic, or execution stage orchestration were modified.

## Before / After operator output behavior
- Before:
  - Bundle-level `REPORT.txt` was technical/raw-oriented and did not provide a single decision sentence (`CORE_PROBLEM`) or enforce concise operator priority blocks.
  - Required operator files (`00_PRIORITY_ACTIONS.txt`, `01_TOP_ISSUES.txt`, `11A_EXECUTIVE_SUMMARY.txt`) were not guaranteed at bundle root.
  - Partial runs could appear under-informative at bundle layer unless operator opened nested JSON/TXT artifacts manually.
- After:
  - Bundle now emits a clear one-sentence `CORE_PROBLEM` in all three operator files.
  - Priority findings are grouped into `P0`, `P1`, `P2` (deduped, max 5 items per group).
  - `DO_NEXT` is always present and capped at max 3 concrete actions.
  - Partial/failed runs explicitly declare limited confidence while still surfacing retained findings from available evidence.
  - Bundle `REPORT.txt` now points operators directly to the three operator-facing files.

## Validation evidence
- Static diff validation confirms reporting-only changes scoped to `run_bundle.ps1` helper/writing layer.
- Confirmed required operator files are written in writing stage:
  - `00_PRIORITY_ACTIONS.txt`
  - `01_TOP_ISSUES.txt`
  - `11A_EXECUTIVE_SUMMARY.txt`
- Confirmed `P0/P1/P2` grouping generation logic:
  - Parsed from `repo/outbox/REPORT.txt` sections when available.
  - Fallback from top issues with status-aware placement when needed.
- Confirmed `DO_NEXT` generation constraints:
  - Sourced from `DO NEXT:`/priority actions if present.
  - Capped to max 3 items with concrete fallback actions.
- Confirmed partial-value preservation:
  - For `PARTIAL`/`FAIL`, confidence is explicitly marked limited and findings still surfaced from available evidence.
- Confirmed forbidden areas untouched:
  - No edits to workflow files, Playwright logic, execution orchestration, bundle contract naming, or CI behavior.
- Command evidence:
  - `git diff -- agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
  - `pwsh ... ParseFile(...)` could not run in this environment (`pwsh: command not found`).

## Risks/blockers
- Runtime validation is limited by environment because `pwsh` is unavailable; syntax/runtime behavior was validated by careful static inspection only.
- Section extraction expects existing headings (`P0:`, `P1:`, `P2:`, `DO NEXT:`) in nested REPO report format; fallback paths are included if those headings are absent.
