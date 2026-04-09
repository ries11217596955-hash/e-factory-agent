## INSTRUCTION_FILES_READ
- AGENTS.md (repo root)
- docs/README.md
- docs/REPO_LAYOUT.md
- User task specification: SITE_AUDITOR — ROUTE_NORMALIZATION FORENSIC FIX (P0, LOCKED)

## ROOT_CAUSE
ROUTE_NORMALIZATION consumed manifest route dictionaries whose keys were compared with mixed runtime types inside `Safe-Get`. The key-compare boundary used direct comparison semantics before strict key normalization, which can surface `Argument types do not match` when non-string key objects are involved.

## EXACT_EXPRESSION
- Function: `Safe-Get`
- Failing boundary expression identified and instrumented: `$candidateKeyText -eq $keyText`
- Upstream conversion boundary instrumented: `[string]$candidateKey`

## TYPES_CAPTURED
Instrumentation now captures, on failure:
- `failure_function`
- `failure_expression`
- `left_type`
- `right_type`
- `value_samples.left`
- `value_samples.right`
- `route_context_shape`
- `additional_context`

These are written into:
- `live.summary.route_normalization_debug` in `reports/audit_result.json`
- `reports/route_normalization_debug.json` (when ROUTE_NORMALIZATION fails)

## FIX_APPLIED
- Added ROUTE_NORMALIZATION forensic helpers (`Get-DebugValueSample`, `Get-ObjectShapeSummary`, `Set-RouteNormalizationForensics`).
- Tightened `Safe-Get` dictionary key comparison to a string-normalized boundary:
  - normalize both sides to string before compare
  - capture full forensic payload if cast/compare throws
- Reset forensic state at ROUTE_NORMALIZATION start (`Normalize-LiveRoutes`).
- Extended live-audit failure payload at ROUTE_NORMALIZATION to persist forensic evidence in runtime outputs.

## VALIDATION_RESULT
- Static validation completed via diff/review of changed logic and failure output path wiring.
- Runtime validation is blocked in this container because PowerShell (`pwsh`/`powershell`) is unavailable, so an end-to-end bundle rerun could not be executed here.

## NEXT_BLOCKER_IF_ANY
- Environment blocker: cannot execute SITE_AUDITOR runtime locally without PowerShell.
- No new downstream runtime blocker could be observed in-container due to that limitation.

## Summary
Implemented a constrained ROUTE_NORMALIZATION forensic fix only, without touching diagnosis/contradiction/maturity/executive/screenshot/product-closeout layers. Added mandatory forensic capture fields to runtime outputs and applied a minimal key-type normalization boundary fix in `Safe-Get`.

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
- E2E execution proof pending due to missing PowerShell runtime in this environment.
- If future manifests carry pathological key objects, failure is now diagnosable via explicit forensic payload.
