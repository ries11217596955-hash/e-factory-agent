## Summary
- Added explicit debug prints in `agent.ps1` for base path and current working directory at startup.
- Added explicit debug prints after report file write to show resolved report path and existence check result.
- Added explicit `pwd` output in workflow debug step immediately after bundle/single-mode execution phase.
- Kept operational logic unchanged (no edits to finalize/decision/warnings flow).
- Updated this task report for `TASK_ID: SITE_AUDITOR_AGENT__ALIGN_WORKDIR_AND_REPORT_PATH`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Agent entrypoint remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Workflow entrypoint remains `.github/workflows/site-auditor-fixed-list.yml`.
- Debug path evidence now includes:
  - `DEBUG BASE PATH: ...`
  - `DEBUG PWD: ...`
  - `DEBUG REPORT PATH: ...`
  - `DEBUG REPORT EXISTS: ...`
  - workflow `pwd` and `ls -R agents/gh_batch/site_auditor_cloud`

## Risks/blockers
- This environment cannot run GitHub Actions jobs, so real runtime values for working directory and output path must be confirmed from workflow logs in GitHub.
- The requested wording references `report.json`, while current script debug hook is attached to the existing `$reportPath` write point (`outbox/REPORT.txt`) to avoid logic changes.
