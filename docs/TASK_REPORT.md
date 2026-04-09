## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)
- `docs/README.md`
- `docs/CLEANUP_PLAN.md`
- `docs/WORKFLOW_RESTORE_NOTE.md`
- `docs/PHASE2_STATUS.md`
- `docs/PHASE3_STATUS.md`
- `docs/FINAL_ROOT_CLOSEOUT.md`
- `docs/history/site_auditor_agent/README.md`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Task
Add a deterministic meta-analysis handoff layer to SITE_AUDITOR by generating `reports/12A_META_AUDIT_BRIEF.txt` from existing evidence.

## Repository scope (Allowed / Forbidden)
- Allowed paths used:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
  - `docs/TASK_REPORT.md`
- Forbidden/protected paths respected:
  - no `.github/workflows/` changes
  - no entrypoint or runtime-flow redesign
  - no Playwright redesign
  - no broad refactor or unrelated cleanup

## Mode
PR-first.

## Current baseline
- Operator outputs existed (`00_PRIORITY_ACTIONS`, `01_TOP_ISSUES`, `11A_EXECUTIVE_SUMMARY`, `REPORT.txt`, JSON truth files), but there was no dedicated analyst handoff layer.
- Analysts had to manually infer comparison targets from mixed operator/technical artifacts.

## Why analyst handoff layer is needed
- Deterministic outputs already capture strong route-level and site-pattern evidence, but there was no explicit bridge telling the next analyst what to compare, distrust, and decide first.
- A structured handoff reduces interpretation drift and makes degraded/PARTIAL honesty explicit.

## Before / After
### BEFORE
- No `reports/12A_META_AUDIT_BRIEF.txt` file generation.
- No deterministic watchlist-oriented analyst brief section in reporting phase.

### AFTER
- Added deterministic `Build-MetaAuditBriefLines` in `agent.ps1` and write phase now emits `reports/12A_META_AUDIT_BRIEF.txt`.
- New file includes all required sections:
  1. AUDIT MISSION
  2. PRIMARY TRUTH FILES
  3. RUN STATUS / CONFIDENCE
  4. DOMINANT SITE PATTERN
  5. SUSPICIOUS ROUTES TO REVIEW
  6. REQUIRED ANALYST CHECKS
  7. CONTRADICTION WATCHLIST
  8. WHAT TO DECIDE FIRST
  9. ANALYST OUTPUT EXPECTATION
- `run_bundle.ps1` now propagates visibility by copying this brief into `audit_bundle/12A_META_AUDIT_BRIEF.txt` and listing it in bundle report outputs.

## Validation evidence
1. **Primary truth file pointers included:** the brief explicitly lists `reports/audit_result.json`, `reports/run_manifest.json`, `reports/visual_manifest.json`, `reports/11A_EXECUTIVE_SUMMARY.txt`, and marks `audit_bundle/REPORT.txt` as secondary.
2. **Suspicious routes included:** routes are deterministically ranked from `route_details` using status + verdict/page-flag scoring and emitted as a prioritized review list.
3. **Dominant pattern included:** sourced from `live.summary.site_pattern_summary.dominant_pattern`, with deterministic fallback to mixed/no-dominant pattern.
4. **Contradiction watchlist included:** deterministic watch items for NOT_EVALUATED/PARTIAL states, healthy-but-thin evidence mismatch, and summary flattening risk.
5. **Decision questions included:** exactly 3 analyst-first decision prompts are emitted under WHAT TO DECIDE FIRST.
6. **Honest degraded behavior:** run-state mapping (`full`, `partial`, `degraded`, `failed`) and confidence-limiters are explicitly generated from final status + page-quality state.

## Non-regression notes
- Existing output paths were preserved and not renamed.
- Existing operator and decision contract remained intact (`p0/p1/p2/do_next`, existing text/json outputs).
- `run_manifest.json` now includes the added report path without changing manifest shape.
- Bundle assembly contract remains intact; only additive visibility for the new analyst brief was introduced.

## Example content
- Suspicious route reference example format: `- /pricing [verdict=WEAK_CONVERSION] :: weak CTA, dead-end flow`.
- Dominant pattern line example format: `- repeated thin-content pattern (REPEATED, 3 route(s))`.
- Contradiction-watch item example: `- Some routes are labeled HEALTHY with low visible text; confirm screenshots are not visually thin.`
- Analyst decision question example: `- Do screenshots confirm the deterministic verdict classes on highest-risk routes?`

## Summary
- Added deterministic meta-analysis handoff file generation in `agent.ps1` (`reports/12A_META_AUDIT_BRIEF.txt`).
- Wired the new report into reporting outputs while preserving all existing output contracts.
- Added deterministic suspicious-route prioritization and contradiction watchlist logic based on existing route/pattern evidence.
- Added explicit run-state + confidence-limiter text for honest PARTIAL/NOT_EVALUATED/FAIL states.
- Added bundle-level visibility for the handoff brief in `run_bundle.ps1`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- Runtime execution validation is limited in this environment because `pwsh`/`powershell` is unavailable.
- Validation in this task is static path/logic verification, not live SITE_AUDITOR execution output.
