## Summary
Implemented the SITE_AUDITOR operator decision-system final push with a strict linear operator flow in outputs only (no normalization/evaluation/screenshot changes). REPORT.txt now forces one dominant direction using PRIMARY PROBLEM + ordered CRITICAL BLOCKERS, includes a single 3-step OPERATOR PATH, and adds binary SUCCESS SIGNAL checks. REMEDIATION_PACKAGE.json now declares linear execution mode and expected impact.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- agents/gh_batch/site_auditor_cloud/run.ps1
- agents/gh_batch/site_auditor_cloud/agent.ps1
- agents/gh_batch/site_auditor_cloud/run_bundle.ps1

## Risks/blockers
- Runtime validation is environment-limited in this container if PowerShell (`pwsh`) is unavailable.
- SUCCESS SIGNAL checks are intentionally binary and deterministic, but final truth still depends on rerun evidence generation.

## CHANGES
- Replaced flat/equal-priority report structure with forced-priority sections in REPORT.txt generation:
  - `SECTION: PRIMARY PROBLEM` (single dominant issue)
  - `SECTION: CRITICAL BLOCKERS` (max 3, explicitly ordered)
- Removed the equal-weight `P1 HIGH IMPACT` section from REPORT.txt output path.
- Replaced generic "DO NEXT" list with `SECTION: OPERATOR PATH` using strict sequential format:
  - `STEP 1 -> ...`
  - `STEP 2 -> ...`
  - `STEP 3 -> ...`
- Added `SECTION: SUCCESS SIGNAL` with observable yes/no checks.
- Updated `reports/REMEDIATION_PACKAGE.json` payload to include:
  - `execution_mode: "linear"`
  - `expected_impact: "..."`

## WHY BETTER FOR OPERATOR
- Forces one primary direction instead of parallel interpretation.
- Reduces cognitive load by limiting blockers to top 3 in explicit order.
- Prevents branching by giving exactly one executable path (max 3 steps).
- Makes completion unambiguous with binary success signals.
- Aligns remediation metadata to a linear execution contract.

## BEFORE vs AFTER
- Before: Operator saw multiple weighted lists (P0/P1) and could treat many items as equally urgent.
- After: Operator sees one PRIMARY PROBLEM and an ordered CRITICAL BLOCKERS set.
- Before: Action guidance was "DO NEXT" and could be interpreted as optional/mixed strategy.
- After: Action guidance is strict `OPERATOR PATH` (`STEP 1 -> STEP 3`) with no branching.
- Before: Completion criteria were less explicit.
- After: `SUCCESS SIGNAL` provides observable yes/no confirmation points.
