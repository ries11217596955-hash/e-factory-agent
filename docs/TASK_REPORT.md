## Summary
- Repaired DECISION_BUILD warnings input boundary by creating canonical `$warningsForDecision` with `Convert-ToDecisionWarningStringArray` from `liveLayer.warnings` before calling `Build-DecisionLayer`.
- Updated `Build-DecisionLayer` warnings contract from `[object[]]` to `[object]` so transport is accepted as-is and normalized once internally.
- Replaced direct warnings materialization from raw `$Warnings` with a local `List[string]` rebuild from `@($normalizedWarnings)` under `array/materialize/warnings`.
- Enforced warnings propagation to P1 exclusively from the local `warningList` (no direct foreach over `$normalizedWarnings` beyond local rebuild).
- Hardened decision output boundary so `decision.warnings` now leaves `Build-DecisionLayer` as canonical `string[]` via `@($warningList.ToArray())`.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Scope remained limited to warnings contour handling around DECISION_BUILD input normalization, materialization, and output emission.

## Risks/blockers
- End-to-end runtime validation for the ZIP execution path was not run in this environment, so confirmation against the exact historical blocker string depends on downstream execution of the patched script.
