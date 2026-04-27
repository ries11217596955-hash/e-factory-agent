## Summary
Implemented a stable artifact packing contract for `SITE_AUDITOR_V2` output enumeration so failure runs still include core evidence and visual outputs. Added explicit stable-file inclusion (`RUN_REPORT.json` if present, `failure_summary.json`, `AGENT_FAILURE_REPORT.txt`, `visual_manifest.json`, `ACTION_REPORT.txt`) and stable-folder inclusion (`screenshots/**`, `summaries/**`) on top of existing scoped artifact collection.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint: `agents/site_auditor_v2/agent.ps1`
- Artifact scope source: `$OutputDir` with restricted collection in:
  - `$OutputDir/captures`
  - `$OutputDir/summaries`
  - `$OutputDir/logs`
  - root-level `$OutputDir` files limited to `.json`, `.txt`, `.png`
  - always-include files when present:
    - `RUN_REPORT.json`
    - `failure_summary.json`
    - `AGENT_FAILURE_REPORT.txt`
    - `visual_manifest.json`
    - `ACTION_REPORT.txt`
  - always-include folders when present:
    - `screenshots/**`
    - `summaries/**`
- `produced_artifacts` paths remain relative to `$OutputDir`, and now include stable visual/failure artifacts even when not surfaced by previous folder-only enumeration.

## Risks/blockers
- End-to-end CI artifact ZIP validation was not executed in this local environment.
- If future mandatory artifacts are added outside the explicit stable file/folder lists, contract lists must be updated to keep ZIP contents complete.
