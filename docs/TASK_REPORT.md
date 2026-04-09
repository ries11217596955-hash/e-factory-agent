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
Upgrade `reports/12A_META_AUDIT_BRIEF.txt` generation from static handoff style to comparison-guided analyst brief behavior.

## Repository scope (Allowed / Forbidden)
- Allowed paths used:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `docs/TASK_REPORT.md`
- Forbidden/protected paths respected:
  - no `.github/workflows/` changes
  - no entrypoint/runtime-flow redesign
  - no Playwright redesign
  - no broad refactor
  - no unrelated file cleanup

## Mode
PR-first.

## Current brief baseline
- BEFORE: `12A_META_AUDIT_BRIEF.txt` existed and was deterministic, but primarily summary/handoff oriented.
- It contained mission, truth files, confidence, dominant pattern, suspicious routes, checks, contradiction watchlist, decision-first questions, and analyst expectation.
- It did not explicitly direct screenshot comparison order, route grouping comparisons, repo-vs-live prompts, concrete contradiction hotspots, or analyst pass sequencing.

## Upgrade design
- Extended `Build-MetaAuditBriefLines` only (deterministic logic preserved).
- Added deterministic route-set derivation from existing evidence (`route_details`, `page_flags`, `verdict_class`, `site_pattern_summary`, run state).
- Added new guidance sections with concise action lines:
  - `SCREENSHOT COMPARISON PLAN`
  - `ROUTE COMPARISON GROUPS`
  - `REPO-vs-LIVE CHECK PROMPTS`
  - `CONTRADICTION HOTSPOTS`
  - `ANALYST FOCUS ORDER`
- Preserved all previously required brief sections and output path contract.

## Before / After
### BEFORE
- Brief was strong as a deterministic summary but lacked comparison-first analyst steering.

### AFTER
- Brief now directs screenshot-first triage based on highest-risk routes, dominant pattern routes, and suspicious HEALTHY routes.
- Brief now includes compact route-to-route comparison groups (worst vs best, suspicious HEALTHY vs weak, contamination vs non-contamination, dominant-pattern cluster).
- Brief now includes deterministic repo-vs-live prompts to reconcile source structure with live page reality.
- Contradiction guidance is now split into explicit `CONTRADICTION HOTSPOTS` + existing `CONTRADICTION WATCHLIST`.
- Brief now includes an ordered `ANALYST FOCUS ORDER` sequence for analyst pass execution.

## Validation evidence
1. **BEFORE validation**
   - Confirmed pre-change function emitted summary-oriented sections and lacked explicit comparison-guided section headers.

2. **AFTER validation**
   - `SCREENSHOT COMPARISON PLAN` section added.
   - `ROUTE COMPARISON GROUPS` section added.
   - `REPO-vs-LIVE CHECK PROMPTS` section added.
   - `CONTRADICTION HOTSPOTS` section added with concrete mismatch checks.
   - `ANALYST FOCUS ORDER` section added with deterministic ordered steps.

3. **NON-REGRESSION validation**
   - Existing sections remain present:
     - audit mission
     - primary truth files
     - run status / confidence
     - dominant site pattern
     - suspicious routes
     - contradiction watchlist
     - what to decide first
     - analyst output expectation
   - Output contract preserved: same target file (`reports/12A_META_AUDIT_BRIEF.txt`) and same generation flow (`Write-OperatorOutputs`).
   - `run_bundle.ps1` was intentionally not changed; operator/bundle behavior remains intact.

4. **EXAMPLE CONTENT (from generated brief templates in code)**
   - Screenshot comparison item example:
     - `Start with highest-risk routes: <route set>.`
   - Route comparison group example:
     - `Worst vs best: [<worst routes>] vs [<best healthy routes>].`
   - Repo-vs-live prompt example:
     - `Do repo/source route structures and templates support what each live route claims to be?`
   - Contradiction hotspot example:
     - `HEALTHY-but-suspicious routes need screenshot verification: <route set>.`
   - Analyst focus order line example:
     - `1) Verify dominant pattern claim against route evidence: <dominant pattern>.`

## Summary
- Upgraded deterministic analyst brief generation to comparison-guided behavior without changing output contract.
- Added screenshot-priority planning from highest-risk and dominant-pattern evidence.
- Added concise route comparison groups for faster route-to-route analyst verification.
- Added repo-vs-live prompts and explicit contradiction hotspots for better human verification.
- Added ordered analyst focus sequence while preserving prior decision/watchlist sections.

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
- Runtime execution proof is limited in this environment because PowerShell execution (`pwsh`/`powershell`) is unavailable.
- Validation is static logic/contract verification via source inspection, not a live generated brief run.
