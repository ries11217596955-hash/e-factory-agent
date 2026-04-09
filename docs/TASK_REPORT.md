## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)
- `docs/README.md`
- `docs/FINAL_ROOT_CLOSEOUT.md`

## Summary
- Restored route normalization resilience in `agent.ps1` so mixed manifest route shapes (including keyed route maps) are normalized safely instead of failing early in live evaluation.
- Added dictionary-safe property access fallback in `Safe-Get` to prevent route normalization stage failures from incompatible dictionary key types.
- Hardened bundle assembly reconciliation in `run_bundle.ps1` so repo artifacts/reports are treated as primary evidence and produce `PARTIAL` truth instead of false "REPO subrun was not captured" / `MALFORMED_SUBRUN_RESULT` outcomes.
- Improved operator-facing aggregation to incorporate `reports/audit_result.json` page-quality state, preserving degraded/partial truth even when REPORT section parsing is incomplete.
- Kept changes minimal and scoped to truthful verdict pipeline surfaces (route normalization + bundle aggregation + report propagation).

## Root cause
- Route normalization depended on direct dictionary access patterns that can throw with heterogeneous dictionary implementations and key types; this could bubble to live-stage catch as `failure_stage=ROUTE_NORMALIZATION` with `evaluation_error="Argument types do not match"`.
- Route extraction assumed `routes` was already a list-like object; keyed route maps were not explicitly normalized, increasing shape-fragility and failure risk.
- Bundle assembly trusted mode-result object integrity more than actual copied repo evidence, so malformed/missing mode results could override real artifacts and produce dishonest missing-subrun summaries.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- REPO execution flow remains unchanged: bundle wrapper invokes existing `run.ps1` REPO mode.
- Bundle/report structure remains unchanged (`audit_bundle/`, `audit_bundle/repo/`, `audit_bundle/bundle_artifacts/`), with truth-reconciliation adjustments only.

## Before / After
### BEFORE
- Live/page-quality path could exit via catch with:
  - `failure_stage = ROUTE_NORMALIZATION`
  - `evaluation_error = "Argument types do not match"`
  - `page_quality_status = NOT_EVALUATED`
- Bundle assembly could emit false-missing outcomes:
  - `REPO subrun was not captured`
  - `MALFORMED_SUBRUN_RESULT`
  even when `repo/reports/*` and/or `repo/outbox/*` existed.
- Operator-facing summaries could under-represent partial truth when REPORT section parsing was sparse.

### AFTER
- Route normalization now safely handles dictionary key access and keyed-route map shapes, reducing ROUTE_NORMALIZATION-stage hard failures for valid-but-mixed route data.
- If REPO mode-result object is missing/malformed but artifacts/reports exist, assembly now reconciles to explicit `PARTIAL` with evidence-based reason instead of false missing-subrun claims.
- Operator aggregation now reads `reports/audit_result.json` and propagates page-quality degraded truth (`NOT_EVALUATED` / `PARTIAL`) into human-facing priorities.

## Validation evidence
- Static code-path evidence for ROUTE_NORMALIZATION hardening:
  - `Safe-Get` dictionary fallback guards added for incompatible dictionary `Contains(...)` behavior.
  - `Resolve-ManifestRoutes` now expands keyed `routes` dictionaries into per-route objects (with route path synthesis from keys).
- Static code-path evidence for truthful bundle reconciliation:
  - Added `Get-RepoEvidence` and assembly reconciliation to prefer observed `repo/reports` / `repo/outbox` presence over malformed/missing mode-result metadata.
  - `MALFORMED_SUBRUN_RESULT` and missing-subrun states are now downgraded to evidence-backed `PARTIAL` when artifacts exist.
- Static code-path evidence for partial-truth propagation:
  - Added `Get-JsonIfPresent` and `audit_result.json` ingestion in operator rollup.
  - Page-quality `NOT_EVALUATED` with route evidence is now surfaced as actionable P1 item rather than being silently flattened.
- Command evidence used:
  - `rg -n "ROUTE_NORMALIZATION|Argument types do not match|page_quality_status|MALFORMED_SUBRUN_RESULT|REPO subrun was not captured" agents/gh_batch/site_auditor_cloud`
  - `git diff -- agents/gh_batch/site_auditor_cloud/agent.ps1 agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Environment limitation:
  - Runtime replay using `pwsh` could not be executed in this environment when unavailable; validation is by deterministic static-path inspection.

## Risks / blockers
- This environment may not provide `pwsh`, so end-to-end runtime confirmation against the latest failing bundle contour may require operator-side execution.
- Route-source schemas beyond currently handled mixed shapes may still require additional targeted normalization if new variants appear.
- Reconciliation intentionally avoids broad architecture changes; if upstream mode-result schema changes further, adapter logic may need small follow-up updates.
