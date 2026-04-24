## Summary
Hardened final `RUN_REPORT` output assembly/serialization boundary for `SITE_AUDITOR_V2` by adding explicit OUTPUT markers, recursive Generic.List-to-array normalization, circular-reference protection, eager serialization preflight, and deterministic write markers.

## Changed files
- agents/site_auditor_v2/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Task report: `docs/TASK_REPORT.md`

## Risks/blockers
- Runtime was **not executed by Codex** against a live target URL in this task, so operator execution is still required to confirm `OUTPUT: WRITE_DONE` in a full run.
- Integer normalization casts integral numeric CLR types to `[int]` during the write boundary; if future schema introduces required non-int integral fields, this boundary must be revisited.
