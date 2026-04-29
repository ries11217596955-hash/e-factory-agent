## Summary
- Fixed artifact lookup in the LINK workflow to search under `agents/site_auditor_v2/output` dynamically instead of assuming artifacts are in `agents/site_auditor_v2/`.
- Updated pre-upload artifact staging to fail strictly when a declared artifact is not found under output runs.
- Updated regression consistency checks to validate declared artifacts from discovered files in output runs.
- Kept artifact names unchanged and did not modify agent runtime code.
- Kept scope limited to workflow artifact lookup behavior.

## Changed files
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint remains: `.github/workflows/site-auditor-v2-link.yml`.
- Agent entrypoint remains unchanged: `agents/site_auditor_v2/agent.ps1`.
- Artifact discovery now resolves files from `agents/site_auditor_v2/output/*/` via `find` in workflow validation steps.

## Risks/blockers
- Minor risk: basename-based lookup could be ambiguous if duplicate filenames exist across multiple run directories.
- No blockers identified for CI artifact upload/validation logic.
