## Summary
Updated `SITE_AUDITOR_V2` artifact reporting to derive `produced_artifacts` strictly from files that actually exist in `agents/site_auditor_v2` (`$OutputDir = $PSScriptRoot`). Removed all manual artifact list mutation logic and all artifact `Add()` paths.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Artifact source directory for `produced_artifacts`: `agents/site_auditor_v2` (resolved via `$OutputDir = $PSScriptRoot`)

## Risks/blockers
- Runtime GitHub Actions validation was not executed in this environment; pipeline confirmation is required for final acceptance checks.
