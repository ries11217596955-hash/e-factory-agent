## Summary
Added a separate external GitHub Actions workflow to run DECISION_BUILD forensic diagnostics on a Windows runner, without wiring forensic execution into production SITE_AUDITOR runtime.
- Added a manual (`workflow_dispatch`) forensic runner workflow.
- Runner executes `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1` with the diagnostic snapshot.
- Workflow logs snapshot path, diagnostic artifact path, and exit status.
- Workflow uploads JSON artifact files matching `decision_build_forensics_*.json`.
- Production agent entrypoints and business logic remain untouched.

## Changed files
- `.github/workflows/site-auditor-decision-forensics.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- External forensic runner (new): `.github/workflows/site-auditor-decision-forensics.yml`
- Harness script (unchanged): `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- Snapshot input (unchanged): `agents/gh_batch/site_auditor_cloud/tools/decision_build_snapshot.diagnostic_cloudlineage.json`
- Production entrypoints (unchanged): `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`

## Risks/blockers
- Workflow execution requires GitHub-hosted Windows runner availability.
- Forensics artifact content depends on runtime conditions in GitHub Actions.
- No local PowerShell execution validation was performed in this Linux container.
