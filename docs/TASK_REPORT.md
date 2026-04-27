## Summary
Root cause: fail-safe RUN_REPORT emission was coupled to REPORT_LAYER object serialization, so when REPORT_LAYER produced incompatible object shapes (e.g., "Argument types do not match"), `failure_summary.json` could still be written but `RUN_REPORT.json` could be skipped.

Implemented a dedicated fail-output contract module (`Write-MinimalFailRunReport`) and wired it in the top-level fail path after the failure-summary attempt. This keeps `agent.ps1` as orchestrator while isolating fail-output logic in a bounded module.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/lib/fail_output.ps1
- agents/site_auditor_v2/ARCHITECTURE.md
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator: `agents/site_auditor_v2/agent.ps1`
- Fail-output module: `agents/site_auditor_v2/lib/fail_output.ps1`
- Architecture memory guard: `agents/site_auditor_v2/ARCHITECTURE.md`
- Failure artifacts written in fail mode:
  - `<run output root>/failure_summary.json`
  - `<run output root>/RUN_REPORT.json` (minimal fail contract)
  - `<run output root>/AGENT_FAILURE_REPORT.txt`

## Risks/blockers
- Validation executed via static parser checks and targeted fail-path contract review, not a full end-to-end live LINK capture in this environment.
- No workflow/capture/route/recon code paths were modified.
