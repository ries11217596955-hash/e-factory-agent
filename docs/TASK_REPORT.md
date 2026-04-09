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
Add a deterministic site-diagnosis layer to `SITE_AUDITOR` so each run emits exactly one top-level site state model, with reason/evidence/confidence, and propagates it into required outputs.

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
  - no unrelated report redesign
  - no unrelated cleanup

## Mode
PR-first.

## Current diagnosis baseline
### BEFORE
- Auditor emitted deterministic route verdicts, site pattern summary, contradiction layer summary, and decision guidance.
- Auditor did **not** emit one deterministic top-level site diagnosis model (single class) per run.
- `audit_result.json`, `11A_EXECUTIVE_SUMMARY.txt`, and `12A_META_AUDIT_BRIEF.txt` did not contain a dedicated diagnosis block with class/reason/evidence/confidence.

## Diagnosis model added
- Added deterministic `Build-SiteDiagnosisLayer` in `agent.ps1`.
- New output object: `decision.site_diagnosis` with:
  - `class` (exactly one)
  - `reason`
  - `evidence` (small deterministic signal list)
  - `confidence` (`HIGH|MEDIUM|LOW`)
- Diagnosis classes implemented (deterministic rule outcomes):
  - `BROKEN_SYSTEM`
  - `TRUST_CONTAMINATED_SYSTEM`
  - `CONTENT_SHELL`
  - `STRUCTURALLY_PRESENT_BUT_THIN`
  - `WEAK_CONVERSION_SYSTEM`
  - `DECISION_CAPABLE_SYSTEM`
  - `HEALTHY_BUT_EARLY`
  - `WEAK_DECISION_SYSTEM`
  - `PARTIAL_PRODUCT_SYSTEM` (default deterministic fallback)
- Confidence reduction rules added for:
  - degraded/partial/not-evaluated runs
  - missing inputs
  - weak route/sample coverage
  - contradiction-rich runs

## Before / After
### BEFORE
- No single top-level deterministic site diagnosis per run.
- No first-class diagnosis reason/evidence/confidence fields in decision/report output.

### AFTER
- Exactly one deterministic top-level diagnosis is emitted under `decision.site_diagnosis`.
- Diagnosis reason, evidence, and confidence are emitted deterministically.
- Propagation added to:
  - `reports/audit_result.json` (through `decision.site_diagnosis`)
  - `reports/11A_EXECUTIVE_SUMMARY.txt`
  - `reports/12A_META_AUDIT_BRIEF.txt`
  - `outbox/REPORT.txt` (minimal useful propagation)

## Validation evidence
1. **AFTER checks (static source validation)**
   - `Build-SiteDiagnosisLayer` added and called from `Build-DecisionLayer`.
   - `decision.site_diagnosis` returned in standard decision object.
   - Fail-path decision now includes deterministic fallback diagnosis (`BROKEN_SYSTEM`, LOW confidence).
   - Executive summary includes diagnosis class/reason/confidence and diagnosis evidence lines.
   - Meta audit brief includes diagnosis class/reason/confidence in run status section.

2. **Required output propagation**
   - `reports/audit_result.json`: includes diagnosis via decision payload.
   - `reports/11A_EXECUTIVE_SUMMARY.txt`: includes diagnosis class/reason/confidence and evidence lines.
   - `reports/12A_META_AUDIT_BRIEF.txt`: includes diagnosis class/reason/confidence.

3. **Non-regression checks**
   - Existing outputs remain generated:
     - `reports/audit_result.json`
     - `reports/11A_EXECUTIVE_SUMMARY.txt`
     - `reports/12A_META_AUDIT_BRIEF.txt`
     - `outbox/REPORT.txt`
   - Existing contradiction layer, clean-state logic, route/site pattern logic, and report paths were preserved.
   - Deterministic contract preserved (rule-based, no opaque probabilistic layer).

4. **Example content**
   - Diagnosis class example: `WEAK_CONVERSION_SYSTEM`
   - Diagnosis reason example: `Routes are mostly non-empty but conversion and onward decision paths are consistently weak.`
   - Diagnosis evidence line example: `route_count=8 empty=1 thin=2 weak_cta=4 dead_end=3 contaminated=0`
   - Diagnosis confidence line example: `Diagnosis confidence: MEDIUM`

## Summary
- Added deterministic top-level site diagnosis classifier and integrated it into decision output.
- Added deterministic diagnosis reason/evidence/confidence output contract.
- Propagated diagnosis into required operator reports without removing existing report fields.
- Added fail-path deterministic diagnosis fallback to preserve one-diagnosis contract.
- Kept change minimal and within requested file scope.

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
- Runtime e2e execution is not performed here because PowerShell runtime execution is not available in this environment.
- Validation is static (source-level) rather than live-generated artifact verification.
