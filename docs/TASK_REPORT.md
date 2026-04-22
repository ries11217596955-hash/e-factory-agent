## Summary
- Removed legacy active `agents/gh_batch` runtime tree.
- Removed three legacy site-auditor workflows from `.github/workflows/` as requested.
- Added a clean `agents/site_auditor_v2` LINK-first scaffold with minimal modules/contracts.
- Implemented `agent.ps1` to support `MODE=LINK` as active mode, deterministic output paths, and honest `0/1` exits.
- Added invocation and expected output documentation for local dry runs.

## Changed files
- Deleted: `agents/gh_batch/**`
- Deleted: `.github/workflows/site-auditor-decision-forensics.yml`
- Deleted: `.github/workflows/site-auditor-fetch-trace.yml`
- Deleted: `.github/workflows/site-auditor-fixed-list.yml`
- Created: `agents/site_auditor_v2/agent.ps1`
- Created: `agents/site_auditor_v2/modules/util_io.ps1`
- Created: `agents/site_auditor_v2/modules/util_json.ps1`
- Created: `agents/site_auditor_v2/contracts/run_report.schema.json`
- Created: `agents/site_auditor_v2/contracts/failure_summary.schema.json`
- Created: `agents/site_auditor_v2/README.md`
- Created: `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Active entrypoint: `agents/site_auditor_v2/agent.ps1`
- Modules: `agents/site_auditor_v2/modules/`
- Contracts: `agents/site_auditor_v2/contracts/`
- Output root: `agents/site_auditor_v2/output/<mode>_<hash>/`

## Risks/blockers
- No blockers encountered.
- The task explicitly required deleting selected files under `.github/workflows/`; this was applied exactly as requested.
