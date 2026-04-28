## Summary
- Fixed SITE_AUDITOR_V2 artifact generation gap for `REPORT_CONTRACT_DIAG.json` by ensuring the diagnostic file is copied to deterministic root output as soon as it is generated.
- Chosen approach: **A) always generate/write `REPORT_CONTRACT_DIAG.json` before artifact collection**.
- This keeps `produced_artifacts` contract truthful: if `REPORT_CONTRACT_DIAG.json` is declared, it now exists at the expected staging path.
- Scope intentionally limited to output-generation behavior and task reporting; summary logic and guards were not changed.
- Goal: unblock pipeline from missing-artifact failure so it can proceed to next validation stage.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Contract diagnostic is still generated at run output path: `agents/site_auditor_v2/output/<run_key>/REPORT_CONTRACT_DIAG.json`.
- Added deterministic mirror write path: `agents/site_auditor_v2/REPORT_CONTRACT_DIAG.json`.
- Artifact assembly entrypoint remains `Get-FinalProducedArtifacts` in `agents/site_auditor_v2/agent.ps1`.
- Finding normalization entrypoint remains `Normalize-FindingContract` invocation in report-layer stage inside `agents/site_auditor_v2/agent.ps1`.

## Risks/blockers
- If execution fails before finding normalization runs, the diagnostic artifact may still be absent (expected for pre-report-layer hard failures).
- Validation in this task is static/script-level (no full SITE_AUDITOR_V2 runtime replay in this environment).
