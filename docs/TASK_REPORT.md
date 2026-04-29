## Summary
- Updated LINK workflow artifact lookup to resolve declared artifacts from `agents/site_auditor_v2/output/**` using `find ... | head -n 1`.
- Replaced strict path assumptions with discovered file path checks while preserving strict failure behavior on missing artifacts.
- Added explicit `MISSING:` and `FOUND:` output lines during both pre-upload staging and regression artifact consistency checks.
- Kept artifact names and folder structure unchanged.
- Limited scope strictly to lookup logic in the target workflow plus this required task report.

## Changed files
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint remains: `.github/workflows/site-auditor-v2-link.yml`.
- Agent entrypoint remains unchanged: `agents/site_auditor_v2/agent.ps1`.
- Artifact lookup now uses discovered file paths from `agents/site_auditor_v2/output` and then copies to `site_auditor_v2_artifact_bundle/${artifact}` for upload.

## Risks/blockers
- If duplicate basenames exist across multiple run directories under `output/`, lookup returns the first match; this follows requested behavior.
- No blockers identified.
