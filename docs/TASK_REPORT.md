## Summary
- Added `ownership_mode` to SITE_AUDITOR_V2 report state with a hardcoded safe default of `EXTERNAL`.
- Updated findings/action text generation so `EXTERNAL` mode only emits analyze/learn/replicate-style actions, while `OWNED` mode keeps fix/update/optimize remediation wording.
- Added `ownership_mode` to `RUN_REPORT.json` and extended `operator_handoff` with ownership context and explicit action-scope explanation.
- Updated run report schema to require and validate the new ownership fields.
- No findings detection, route sampling, or evidence reconciliation logic was changed; only report/action phrasing and scope constraints were updated.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report contract remains: `agents/site_auditor_v2/contracts/run_report.schema.json`.
- Report artifacts remain under `agents/site_auditor_v2/output/<run_id>/` with deterministic mirrors in `agents/site_auditor_v2/`.

## Risks/blockers
- `ownership_mode` is currently hardcoded to `EXTERNAL`; producing `OWNED` output requires a future explicit input/plumbing change.
- Downstream consumers validating `RUN_REPORT.json` must use the updated schema that includes `ownership_mode` and new `operator_handoff` fields.
- Rollback instructions:
  1. `git revert <commit_sha>`
  2. Or restore files directly: `git checkout -- agents/site_auditor_v2/agent.ps1 agents/site_auditor_v2/contracts/run_report.schema.json docs/TASK_REPORT.md`
