# AGENT_PS1_DEEP_AUDIT

## FILE OVERVIEW
- Target: `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- File size: 3266 lines, 42 function blocks.
- Role: single-file orchestration for source audit + live capture + route normalization + page-quality scoring + contradiction/meta decision layers + output contract enforcement.
- Runtime entry wrapper files (`run.ps1`, `run_bundle.ps1`) invoke this script and rely on its output artifacts (`REPORT.txt`, `audit_result.json`, done markers).

## PIPELINE STAGE MAP
`Invoke-LiveAudit` stage machine (via `$liveStage`):
1. `CAPTURE`
   - Validates `capture.mjs` exists.
   - Runs `node capture.mjs` with `REPORTS_DIR`.
2. `LOAD_VISUAL_MANIFEST`
   - Reads `reports/visual_manifest.json` and parses JSON.
3. `ROUTE_NORMALIZATION`
   - Calls `Normalize-LiveRoutes`.
   - Writes `reports/route_normalization_trace.json` (success path and catch path).
4. `ROUTE_MERGE`
   - Splits normalized routes into healthy vs errored.
   - Computes screenshot totals.
5. `PAGE_QUALITY_BUILD`
   - Calls `Build-PageQualityFindings`.
   - Builds rollups, pattern summary, evidence coverage, warnings/findings.
6. Return `New-LiveLayer` with summary + route_details.

Failure path:
- Catch returns `New-LiveLayer` with `page_quality_status=NOT_EVALUATED`, `failure_stage=$liveStage`, fallback route details, and optional route-normalization debug payload.

## FUNCTION MAP
Major groups:
1. **Normalization/forensics core**
   - `Safe-Get`, `Convert-To*Safe`, `Resolve-ManifestRoutes`, `Normalize-LiveRoutes`.
   - Route trace + aggregate trace + forensic snapshot helpers.
2. **Source/live acquisition**
   - `Invoke-SourceAuditRepo`, `Invoke-SourceAuditZip`, `Invoke-LiveAudit`.
3. **Quality/diagnosis/decision layers**
   - `Build-PageQualityFindings`, `Build-ContradictionLayer`, `Build-SiteDiagnosisLayer`, `Build-MaturityReadinessLayer`, `Build-AuditorBaselineCertification`, `Build-DecisionLayer`.
4. **Output/contract**
   - `Write-OperatorOutputs`, `Ensure-OutputContract`.
5. **Main execution block**
   - MODE switch (`REPO`, `ZIP`, `URL`) then decision + output + fail-safe fallback.

## DEFECT MAP
> This is a structural/static audit map (not a runtime rewrite). Severity is based on failure likelihood and blast radius.

### D1 — PARSE_INTEGRITY (MEDIUM, stabilized but fragile)
- Historical parse failure region is inside `Invoke-LiveAudit` catch block around route-normalization debug writer.
- Current file appears balanced, but this region remains high-risk because it is deeply nested with repeated try/catch and repeated artifact writes.
- Risk: future micro-edits can easily reintroduce a stray brace or catch alignment drift.

### D2 — BLOCK_BOUNDARY_DRIFT (MEDIUM)
- Several long nested blocks (`Normalize-LiveRoutes`, `Invoke-LiveAudit`, `Write-OperatorOutputs`) exceed easy manual verification range.
- High local nesting + repeated fallback catches increase probability of boundary drift during patching.

### D3 — HYBRID_LOGIC_DRIFT (HIGH)
- File contains both legacy/simple flows and hardened forensic flows in the same function zones.
- Example: route normalization has OP1..OP5A instrumentation plus fallback derivation paths and per-phase trace writes.
- This “layered retrofit” shape indicates accumulated whole-file replacements and partial merges.

### D4 — UNSAFE_ARRAY_MATERIALIZATION (MEDIUM)
- Repeated use of `@(...)` over values that may already be arrays, scalars, list objects, or enumerable pipelines.
- Inconsistent scalarization patterns exist across file (`Count`, `Measure-Object`, array cast paths), increasing risk of subtle count drift.

### D5 — UNSAFE_MEASURE_OBJECT_USAGE (LOW-MEDIUM)
- `Measure-Object` based count fallback in normalization can hide non-standard enumerables and implicit pipeline coercion edge cases.
- Current logic compensates, but path complexity makes behavior difficult to reason about for maintainers.

### D6 — FALLBACK_TRUTH_DRIFT (HIGH)
- Failure outputs may look data-rich due to fallback hydration (`New-RouteNormalizationFallbackDebug`, fallback route details) even when stage failed.
- Risk: operators may over-trust fallback diagnostics as equivalent to successful route evaluation.

### D7 — LABEL_EXPRESSION_MISMATCH (MEDIUM)
- Operation labels and expressions are not always semantically aligned with actual implementation details.
- Example pattern: OP labels referencing `Math.Max` semantics while code now uses explicit floor logic; labels can mislead incident triage.

### D8 — OUTPUT_CONTRACT_RISK (MEDIUM)
- Output contract is robust, but duplicated write surfaces (`Write-OperatorOutputs` + `Ensure-OutputContract`) can yield partially contradictory artifacts when mid-pipeline failure occurs.
- Risk: operator sees contract-complete outputs that are structurally valid but semantically degraded.

### D9 — REPO_HYGIENE_RISK (MEDIUM)
- Script behavior depends on environment and path assumptions (`$env:GITHUB_WORKSPACE`, `$env:TARGET_REPO_PATH`, `BASE_URL`, Node availability).
- If repo state or runner tooling drifts, contract may still be emitted while underlying capture/audit quality degrades.

### D10 — DEAD_OR_DUPLICATE_BRANCHES (LOW-MEDIUM)
- Multiple fallback branches and status transitions are close in purpose (e.g., evaluated/partial/not-evaluated paths + catch fallback path).
- Some branches may be effectively duplicate safeguards but remain because of incremental patch history.

## ISSUE FAMILIES
- `PARSE_INTEGRITY`: historical and still fragile in deeply nested catch/debug block.
- `BLOCK_BOUNDARY_DRIFT`: long nested blocks with repeated try/catch.
- `HYBRID_LOGIC_DRIFT`: old/new logic coexisting in route normalization and output composition.
- `UNSAFE_ARRAY_MATERIALIZATION`: mixed list/array/enumerable coercion idioms.
- `UNSAFE_MEASURE_OBJECT_USAGE`: counting via fallback pipeline coercion.
- `FALLBACK_TRUTH_DRIFT`: degraded runs can still generate rich-looking fallback payloads.
- `LABEL_EXPRESSION_MISMATCH`: OP labels and expression text partially out of sync with code semantics.
- `OUTPUT_CONTRACT_RISK`: guaranteed artifact creation can mask degraded semantics.
- `REPO_HYGIENE_RISK`: tool/path/env assumptions affect reliability.
- `DEAD_OR_DUPLICATE_BRANCHES`: protective branches that may overlap in effect.

## HYBRID/DRIFT ZONES
1. `Normalize-LiveRoutes` OP1..OP5A instrumentation + older-style data handling in same function.
2. `Invoke-LiveAudit` success writer and catch writer both generating normalization trace artifacts.
3. Route-level verdict + contradiction + diagnosis + product closeout layers assembled in one monolithic file, increasing coupling.
4. `Write-OperatorOutputs` assembling many derived artifacts while `Ensure-OutputContract` can overwrite fallback essentials.

## RUNTIME HOTSPOTS
1. **`ROUTE_NORMALIZATION`**: highest complexity and forensic write density.
2. **`ROUTE_MERGE`**: status coercion and healthy/error partition can drift with mixed status types.
3. **`PAGE_QUALITY_BUILD`**: multi-signal deterministic classification with many thresholds.
4. **Output layer**: cross-artifact consistency under failure and partial states.
5. **Main mode switch + required input validation**: mode-specific failure behavior drives downstream truthfulness.

## PROPOSED REPAIR BATCHES
### Batch 1 (safest, PR-small): Structural guardrails only
- Add zero-behavior-change block boundary comments/anchors in `Invoke-LiveAudit` and `Normalize-LiveRoutes`.
- Normalize try/catch section headers for easier diff review.
- Goal: lower future parse/block drift risk.

### Batch 2: Label/expression truth alignment
- Align OP labels / expression strings with actual implemented operations.
- No behavioral changes; diagnostics fidelity only.

### Batch 3: Array/count normalization utility consolidation
- Introduce one internal count/materialization helper and replace repeated ad-hoc scalarization logic.
- Keep outputs identical; reduce drift risk.

### Batch 4: Fallback truth hardening
- Add explicit degraded-run markers into fallback sections used by operator-facing artifacts.
- Ensure fallback payload cannot be mistaken for full-stage success.

### Batch 5: Output consistency checks
- Add deterministic consistency check before final write manifest (e.g., stage status vs generated rollups).
- Keep output contract intact.

### Batch 6: Dead/duplicate branch pruning (optional, last)
- Remove or collapse clearly redundant fallback branches only after behavior snapshots exist.

## REPAIR ORDER
1. Batch 1 — structural guardrails.
2. Batch 2 — label/expression alignment.
3. Batch 3 — materialization/count helper normalization.
4. Batch 4 — fallback truth hardening.
5. Batch 5 — output consistency checks.
6. Batch 6 — branch pruning.

## FIRST SMALL PR-SAFE REPAIR SEQUENCE
1. Add block boundary markers around `Invoke-LiveAudit` catch route-normalization debug segment.
2. Add block boundary markers around `Normalize-LiveRoutes` OP2/OP3/OP4 aggregate sections.
3. Add one comment legend mapping OP labels to stage purpose.
4. Align any clearly stale OP expression text that no longer matches arithmetic implementation.
5. Add one explicit `degraded_run = true` marker in live-summary catch return path (no contract field removal).

## WHAT NOT TO TOUCH
- Do **not** remove output contract files or done-marker logic.
- Do **not** remove trace/debug/report layers; only harden and clarify.
- Do **not** redesign decision taxonomy/class names in this phase.
- Do **not** refactor other agents or shared workflows.
- Do **not** introduce large behavioral rewrites in a single PR.
