## Summary
- Added a self-diagnostic failure report writer in `agents/site_auditor_v2/agent.ps1` that always emits `AGENT_FAILURE_REPORT.txt` when the run ends in `FAIL`.
- Implemented a diagnostics content contract with required fields: `STAGE_FAILED`, `LAST_COMPLETED_STAGE`, `ERROR_TYPE`, `RAW_ERROR_MESSAGE`, `INTERPRETATION`, `LIKELY_CAUSE`, and `NEXT_FIX_STEP`.
- Added error classification mapping rules to normalize failures into `RUNTIME_EXCEPTION`, `CONTRACT_VIOLATION`, or `OBJECT_LIMITATION`.
- Added stage-aware diagnosis using the existing stage trace to include `EXPECTED_NEXT_STAGE` and explain what should have happened next.
- Added human translation rules (including explicit conversion of `Argument types do not match` to a PowerShell 5.1 runtime-helper mismatch explanation) and fallback behavior so the diagnostic file is still written even if the diagnostic writer itself errors.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added helper functions:
    - `Get-StageSequence`
    - `Get-NextStageName`
    - `Get-FailureErrorClassification`
    - `Get-HumanFailureInterpretation`
    - `Write-AgentFailureReport`
  - Added output paths:
    - `<run_output>/AGENT_FAILURE_REPORT.txt`
    - deterministic mirror `agents/site_auditor_v2/AGENT_FAILURE_REPORT.txt`
  - Updated fail-finalization flow to:
    - always write `AGENT_FAILURE_REPORT.txt`
    - write fallback report content if diagnostic write fails
    - register the artifact in `produced_artifacts` and `linked_artifacts`
- `docs/TASK_REPORT.md`
  - Updated with this task’s implementation, mapping rules, and examples.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged: `agents/site_auditor_v2/agent.ps1`.
- Stage flow remains unchanged and is only reused for diagnosis context:
  - `ENTRY`
  - `LINK_FETCH`
  - `ROUTE_EXTRACTION`
  - `ROUTE_SELECTION`
  - `CAPTURE`
  - `RECONCILIATION`
  - `SURFACE_CONTEXT`
  - `REPORT_LAYER`
- New fail artifact path:
  - `agents/site_auditor_v2/output/<run_key>/AGENT_FAILURE_REPORT.txt`

## Risks/blockers
- Could not execute full end-to-end runtime validation of PowerShell-specific behavior in this environment; checks were limited to static/syntax validation.
- Error-classification rules are pattern-based; unknown future error strings default to `RUNTIME_EXCEPTION` until explicit mapping is added.
- `OBJECT_LIMITATION` classification is now available in diagnostics mapping, but run outcome semantics were intentionally not broadened or refactored in this patch.

### Mapping rules (diagnostic layer)
- `ROUTE_CONTRACT_BREACH`, `*CONTRACT*`, or `CONSISTENCY_LOCK_FAILED*` → `CONTRACT_VIOLATION` (`ERROR_TYPE=contract`)
- `*LIMITATION*` or `*NOT_IMPLEMENTED*` → `OBJECT_LIMITATION` (`ERROR_TYPE=object`)
- Any other error → `RUNTIME_EXCEPTION` (`ERROR_TYPE=runtime`)

### Example outputs
- Example (runtime helper mismatch):
  - `RAW_ERROR_MESSAGE: Argument types do not match`
  - `INTERPRETATION: PowerShell 5.1 constructor mismatch in runtime helper.`
  - `NEXT_FIX_STEP: Replace ambiguous constructor calls with runtime-safe helper factories and rerun from ENTRY.`
- Example (route extraction empty):
  - `RAW_ERROR_MESSAGE: ROUTE_EXTRACTION_FAILED_NO_INTERNAL_LINKS`
  - `INTERPRETATION: Route extraction found links but none were accepted as internal routes.`
  - `NEXT_FIX_STEP: Review URL canonicalization and internal-domain matching rules for LINK_FETCH output.`
