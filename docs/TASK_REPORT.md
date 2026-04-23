## Summary
- Added a dedicated self-build protocol module for `SITE_AUDITOR_V2` with a strict failure class contract (`AGENT_DEFECT`, `OBJECT_DEFECT`, `AUDIT_LIMITATION`).
- Updated failure handling to always classify failures and persist the class in both `RUN_REPORT.json` failure metadata and `failure_summary.json` (`fail_class`).
- Added mandatory FAIL-time self-diagnostic artifact generation: `AGENT_FAILURE_REPORT.txt` with required operator-readable fields.
- Added mandatory FAIL-time operator handoff artifact generation: `AGENT_OPERATOR_HANDOFF.json` with required next-step contract (`next_1_fix`, `next_2_optional`, `next_3_optional`, `rerun_condition`).
- Added local build-ladder lock contract (layers 1–6) and encoded feature-progress gate for layers 2–4.

## Changed files
- `agents/site_auditor_v2/modules/self_build_protocol.ps1`
  - New protocol helpers:
    - `Get-FailureClass`
    - `Get-BuildLadderContract`
    - `New-AgentFailureReportText`
    - `New-OperatorHandoffContract`
- `agents/site_auditor_v2/agent.ps1`
  - Imports new self-build module.
  - Adds artifact paths for:
    - `AGENT_FAILURE_REPORT.txt`
    - `AGENT_OPERATOR_HANDOFF.json`
  - Extends linked artifact map with the two new artifacts.
  - Adds `self_build_protocol` runtime section to the run report contract.
  - Ensures fail classification is applied during early fail, catch fail, and final fail serialization.
  - Ensures every fail writes both required artifacts and deterministic copies.
  - Emits 2–3 explicit next moves through operator handoff artifact contract.
  - Applies build-ladder lock status to the runtime contract (`feature_progress_allowed`).
- `docs/TASK_REPORT.md`
  - Replaced with this report for PACK D0 scope.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains unchanged:
  - `agents/site_auditor_v2/agent.ps1`
- Added protocol helper module path:
  - `agents/site_auditor_v2/modules/self_build_protocol.ps1`
- New fail artifacts emitted under the run output root and deterministic root:
  - `AGENT_FAILURE_REPORT.txt`
  - `AGENT_OPERATOR_HANDOFF.json`

## Risks/blockers
- Runtime verification in-container is limited because `pwsh` may be unavailable.
- Failure classification mapping is stage-based + known-code-based and may need tuning as new failure codes are introduced.
- Rollback instructions:
  1. `git checkout -- agents/site_auditor_v2/agent.ps1`
  2. `git checkout -- agents/site_auditor_v2/modules/self_build_protocol.ps1`
  3. `git checkout -- docs/TASK_REPORT.md`
  4. Re-run `SITE_AUDITOR_V2` LINK mode in target runtime.
