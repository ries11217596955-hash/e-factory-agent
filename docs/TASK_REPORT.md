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
- `docs/history/site_auditor_agent/V3_5_REPAIR_INTELLIGENCE.txt`
- `docs/history/site_auditor_agent/V3_4_0_REPORT_OUTPUT_FIX.txt`
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Task
Upgrade SITE_AUDITOR from a flag-based checker to a decision-grade page-quality auditor while preserving deterministic behavior and existing output contract.

## Repository scope (Allowed / Forbidden)
- Allowed paths used:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `docs/TASK_REPORT.md`
- Forbidden/protected paths respected:
  - no `.github/workflows/` changes
  - no entrypoint/routing/runtime-flow redesign
  - no Playwright redesign
  - no broad architecture refactor
  - no unrelated cleanup

## Mode
PR-first.

## Requirements
Implemented deterministic reasoning upgrades for:
- route verdict classification
- site-wide repeated pattern detection
- smarter priority grouping (trust/conversion/coverage/secondary)
- concrete do_next action shaping (max 3)
- preserved existing report/bundle file contract

## Current baseline (BEFORE)
- Existing route-level low-level flags existed (`empty`, `thin`, `weak_cta`, `dead_end`, `ui_contamination`).
- Existing decision layer mostly mapped flag counts to P0/P1/P2 mechanically.
- Existing `do_next` text was generic and not tied to dominant evidence clusters.

## Upgrade design (AFTER)
1. **Route verdict classification (deterministic):**
   - Added `Get-RoutePrimaryVerdict` and emitted one `verdict_class` per route in `route_details`.
   - Verdict classes now include: `EMPTY`, `THIN`, `WEAK_DECISION`, `WEAK_CONVERSION`, `DEAD_END`, `TRUST_CONTAMINATED`, `HEALTHY`, `MIXED`.

2. **Site-wide pattern detection:**
   - Added `Build-SitePatternSummary` to detect repeated (>=2 routes) vs isolated (=1 route) pattern clusters.
   - Added `site_pattern_summary` into `live.summary` for downstream reporting.

3. **Priority reasoning improvements:**
   - `Build-DecisionLayer` now emits priority text grouped by impact type:
     - trust blocker
     - conversion blocker
     - coverage/content blocker
     - secondary optimization issue
   - Preserved `p0`, `p1`, `p2` output contract.

4. **Operator action shaping:**
   - `do_next` is now evidence-shaped and capped to 3 items.
   - Actions prioritize empty-route restoration, CTA-path restoration, contamination cleanup, and rerun after dominant pattern cluster fixes.

5. **Operator/report propagation:**
   - `00_PRIORITY_ACTIONS.txt` now mirrors `do_next` (numbered) when present.
   - `11A_EXECUTIVE_SUMMARY.txt` and `REPORT.txt` now include repeated/isolated pattern counts and dominant pattern label.

## Validation evidence
### 1) Route verdict class example
- Static reasoning path in `Build-PageQualityFindings`:
  - if route is empty/error => verdict `EMPTY`
  - else if contamination exists => `TRUST_CONTAMINATED`
  - else weak CTA + dead-end => `WEAK_DECISION`
  - else mapped to `WEAK_CONVERSION` / `DEAD_END` / `THIN` / `HEALTHY` / `MIXED`

### 2) Repeated pattern detection example
- `Build-SitePatternSummary` classifies each pattern key (empty/thin/weak_cta/dead_end/contaminated):
  - `routes_affected >= 2` => `scope = REPEATED`
  - `routes_affected == 1` => `scope = ISOLATED`
- Produces `repeated_pattern_count`, `isolated_pattern_count`, and `dominant_pattern`.

### 3) Improved priority classification example
- In `Build-DecisionLayer`:
  - contamination >=2 => `P0 Trust blocker`
  - empty >=2 => `P0 Coverage/content blocker`
  - conversion route pressure (weak_cta + dead_end) >=3 => conversion blocker message
  - thin=1 and small conversion pressure => secondary optimization in lower priority

### 4) Improved do_next line example
- Deterministic action shaping now emits concrete lines such as:
  - `Fix empty routes first (N route(s)) to restore core page coverage.`
  - `Restore CTA path and onward navigation on weak-conversion routes (N observations).`
  - `Rerun after fixing the dominant pattern cluster: <label>.`

## Non-regression notes
- Existing outputs remain present:
  - `reports/audit_result.json`
  - `reports/HOW_TO_FIX.json`
  - `reports/00_PRIORITY_ACTIONS.txt`
  - `reports/01_TOP_ISSUES.txt`
  - `reports/11A_EXECUTIVE_SUMMARY.txt`
  - `reports/run_manifest.json`
  - `outbox/REPORT.txt`
- Existing bundle/operator contract not changed in structure; fields were enriched, not removed.
- No fake PASS logic added; existing status gating still derives from evidence and execution state.
- Degraded behavior remains explicit: `NOT_EVALUATED`/`PARTIAL` paths still surface as warnings/P0 and shape do_next accordingly.

## Summary
- Upgraded `agent.ps1` with deterministic route verdict classification and per-route verdict emission.
- Added site-wide repeated/isolated pattern detection with dominant cluster reporting.
- Improved decision-layer priority semantics while preserving `p0`/`p1`/`p2` contract.
- Improved operator-facing guidance by generating concrete, evidence-linked `do_next` actions (max 3).
- Updated report text outputs to carry new pattern intelligence without changing file-level contract.

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
- Runtime validation remains limited in this environment due missing PowerShell runtime (`pwsh` / `powershell`).
- Therefore validation evidence is static-code-path verification in this task, not full execution artifacts.
