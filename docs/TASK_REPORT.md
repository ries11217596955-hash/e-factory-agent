## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/README.md`
- `docs/CLEANUP_PLAN.md`
- `docs/WORKFLOW_RESTORE_NOTE.md`
- `docs/PHASE2_STATUS.md`
- `docs/PHASE3_STATUS.md`
- `docs/FINAL_ROOT_CLOSEOUT.md`
- `docs/history/site_auditor_agent/README.md`
- `docs/legacy_root_notes/index.md`
- `docs/legacy_root_notes/APPLY_NOTE.md`

## Task
Add a deterministic contradiction-detection layer to `SITE_AUDITOR` so cross-layer mismatches are explicitly surfaced in route/site outputs and analyst-facing reports.

## Repository scope (Allowed / Forbidden)
- Allowed paths used:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `docs/TASK_REPORT.md`
- Forbidden/protected paths respected:
  - no `.github/workflows/` changes
  - no workflow edits
  - no Playwright redesign
  - no repo binding redesign
  - no broad architecture rewrite
  - no unrelated cleanup/refactor
  - no site/content changes

## Mode
PR-first.

## Current contradiction baseline
- BEFORE: deterministic outputs already had route verdicts, page flags, site pattern summary, and contradiction-oriented analyst wording in `12A_META_AUDIT_BRIEF.txt` generation.
- BEFORE: contradiction handling was mostly implicit (heuristics in brief/watchlist text) rather than a first-class deterministic data layer.
- BEFORE: no dedicated contradiction object in `audit_result.json` and no explicit contradiction rollup in `11A_EXECUTIVE_SUMMARY.txt`/core decision output.

## Contradiction model added
- Added deterministic route-level contradiction candidates during page-quality evaluation:
  - `HEALTHY_BUT_VISUALLY_WEAK`
  - `NON_EMPTY_BUT_LOW_VALUE`
- Added deterministic cross-layer contradiction aggregator (`Build-ContradictionLayer`) to produce:
  - route-level candidates
  - site-level candidates
  - class counts and totals
- Added site-level contradiction classes where data supports them:
  - `SOURCE_EXPECTS_MORE_THAN_LIVE_DELIVERS`
  - `SUMMARY_UNDERSTATES_PATTERN`
  - `PARTIAL_BUT_EVIDENCE_RICH`
- Wired contradiction summary into decision output (`decision.contradiction_summary`) and clean-state labeling (`CLEAN` / `SUSPICIOUSLY_CLEAN` / `NOT_CLEAN`).

## Before / After
### BEFORE
- Contradictions were mostly hinted in analyst instructions/hotspots text.
- No normalized contradiction candidate structure was exported as primary deterministic evidence.
- Executive summary top-line could be read as clean without an explicit “suspiciously clean” gate.

### AFTER
- Deterministic contradiction candidates are generated and attached to route details plus site-level rollups.
- Contradiction summary is propagated to:
  - `reports/audit_result.json` (via `live.summary.contradiction_summary` and `decision.contradiction_summary`)
  - `reports/11A_EXECUTIVE_SUMMARY.txt` (counts/classes + suspiciously-clean warning)
  - `reports/12A_META_AUDIT_BRIEF.txt` (run-level contradiction counts/classes + stronger analyst check)
- Clean-vs-suspiciously-clean distinction is now explicit via `decision.clean_state` and summary/report lines.

## Validation evidence
1. **BEFORE validation**
   - Verified pre-change logic had page quality, verdicts, and pattern summaries but lacked a dedicated contradiction layer object and contradiction rollups in executive summary output.

2. **AFTER validation**
   - Contradiction candidates are explicitly generated (`route_details[*].contradiction_candidates` + `decision/live contradiction_summary`).
   - Route-level contradiction path represented (`HEALTHY_BUT_VISUALLY_WEAK`, `NON_EMPTY_BUT_LOW_VALUE`).
   - Site-level contradiction path represented (`SOURCE_EXPECTS_MORE_THAN_LIVE_DELIVERS`, `SUMMARY_UNDERSTATES_PATTERN`, `PARTIAL_BUT_EVIDENCE_RICH`).
   - Analyst-facing outputs include contradiction totals/classes and extra deterministic review prompt.
   - Clean-vs-suspiciously-clean state is explicitly labeled and propagated.

3. **NON-REGRESSION validation**
   - Existing output files and generation flow remain intact:
     - `reports/audit_result.json`
     - `reports/11A_EXECUTIVE_SUMMARY.txt`
     - `reports/12A_META_AUDIT_BRIEF.txt`
     - outbox `REPORT.txt`
   - No report path/contract removal.
   - Deterministic rule-based contract preserved (no probabilistic/LLM-only inference layer).

4. **EXAMPLE CONTENT**
   - Contradiction candidate line example:
     - `Contradiction candidate [NON_EMPTY_BUT_LOW_VALUE]: bodyTextLength=... avoids EMPTY, but weak_cta=... dead_end=...`
   - Route contradiction example:
     - route with `verdict=HEALTHY` and weak/low evidence emits `HEALTHY_BUT_VISUALLY_WEAK` candidate.
   - Site-level contradiction summary line example:
     - `repeated_pattern_count=... with aggregate issue observations=... can make top-line summary sound milder...`
   - Analyst-facing strengthened prompt example:
     - `Prioritize contradiction classes from the deterministic layer before final interpretation.`

## Summary
- Added deterministic contradiction candidate generation at route and site levels.
- Introduced explicit contradiction rollups/class counts and propagated them into decision/live summary structures.
- Strengthened executive summary and analyst brief with contradiction totals/classes and suspiciously-clean warnings.
- Preserved existing report contract and existing file outputs.
- Kept change minimal and scoped to allowed files only.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- Runtime execution validation is limited here because `pwsh`/`powershell` is not available in this environment.
- Validation was performed via static source inspection and deterministic logic tracing; not full live end-to-end report generation.
