## Summary
Updated `SITE_AUDITOR_V2` artifact collection to recursively enumerate files under `$OutputDir` and compute relative paths from full paths, preserving nested subfolder structure in `produced_artifacts`.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Artifact base directory for `produced_artifacts`: `agents/site_auditor_v2` (resolved from `$OutputDir = $PSScriptRoot`)
- Produced artifact path format: `<relative_path_from_agents/site_auditor_v2>` (including nested folders)

## Risks/blockers
- GitHub Actions artifact upload/visibility validation was not executed in this local environment.
