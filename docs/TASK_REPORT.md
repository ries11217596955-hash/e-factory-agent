## Summary
- Enforced the `decision.do_next` output contract in `DECISION_BUILD` so the field is always populated with executable steps.
- Added post-generation filtering to remove null/empty items and detect weak abstract actions (`improve`, `analyze`).
- Added deterministic fallback steps when generated actions are empty or weak.
- Enforced maximum length of 3 steps and forced final assignment back to `decision.do_next`.
- Left audit logic and reasoning flow unchanged.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry point unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Output contract target unchanged: `decision.do_next` in DECISION_BUILD packaging path.

## Risks/blockers
- Validation here is static/code-level; end-to-end runtime verification depends on running the full agent workflow with required inputs.
