# MERGE_FILTER

PASS_FOR_MERGE:
- file path: `agents/site_auditor_v2/agent.ps1`
  - change description: Added declared-artifact JSON contract validation (`Test-JsonArtifactFile`, `Test-DeclaredArtifactContract`) and explicit `ARTIFACT_CONTRACT_BREACH` fail path.
  - verification result: Static code review complete; bounded scope respected; runtime verification HOLD due to missing PowerShell.
- file path: `agents/site_auditor_v2/agent.ps1`
  - change description: Hardened RUN_REPORT with `failure_summary`, `operator_handoff.must_read_first`, and `next_strongest_move`; enforced no PASS on route/artifact contract breach.
  - verification result: Static code review complete; fail-guard logic present; runtime execution not possible in this container.
- file path: `tests/fixtures/site_auditor_v2/happy_path/*`
  - change description: Added deterministic happy-path fixture artifacts and expected outcome marker.
  - verification result: JSON structure reviewed and parseable.
- file path: `tests/fixtures/site_auditor_v2/route_breach/*`
  - change description: Added deterministic route-breach fixture with explicit ROUTE_CONTRACT_BREACH expectation.
  - verification result: JSON structure reviewed and parseable.
- file path: `tests/fixtures/site_auditor_v2/artifact_breach/*`
  - change description: Added deterministic artifact-breach fixture with explicit ARTIFACT_CONTRACT_BREACH expectation.
  - verification result: JSON structure reviewed and parseable.
- file path: `tests/fixtures/site_auditor_v2/partial_run/*`
  - change description: Added deterministic partial-run fixture preserving contract compliance.
  - verification result: JSON structure reviewed and parseable.
- file path: `tests/validate_link_contract_fixtures.ps1`
  - change description: Added deterministic fixture validation script for happy, route breach, artifact breach, and partial scenarios.
  - verification result: Script content reviewed; runtime HOLD because PowerShell executable is unavailable.
- file path: `docs/TASK_REPORT.md`
  - change description: Replaced with phase-by-phase mission report including rollback contracts.
  - verification result: Documentation-only; manually reviewed.
- file path: `docs/MERGE_FILTER.md`
  - change description: Added PASS/HOLD/FAIL merge filter classification.
  - verification result: Documentation-only; manually reviewed.

HOLD:
- file path: `agents/site_auditor_v2/agent.ps1`
  - reason not ready: End-to-end LINK mode verification (Phase 6 gate) is unexecuted in this environment due to missing `pwsh` runtime.
- file path: `tests/validate_link_contract_fixtures.ps1`
  - reason not ready: Deterministic script execution could not be performed in-container (`pwsh` missing).

FAIL:
- None.
