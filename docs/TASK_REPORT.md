## Summary
Restricted `SITE_AUDITOR_V2` `produced_artifacts` to output-only files by introducing an explicit extension whitelist (`.json`, `.txt`, `.png`) and explicit allowed output folders (`captures`, `summaries`, `logs`). Replaced broad `$OutputDir` recursive collection with a scoped helper that only aggregates files from those output zones plus allowed root-level output files.

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
- `produced_artifacts` paths remain relative to `$OutputDir`.

## Risks/blockers
- End-to-end artifact upload validation was not executed in this local environment.
- If future required output files use extensions outside the whitelist, they will be excluded until the whitelist is updated.
