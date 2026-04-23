## Summary
- Implemented a strict page-signal model for `agents/site_auditor_v2` LINK mode using only three hard signals: `PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, and `NO_ACTION_PATH`.
- Removed weak signal types from the findings generation pipeline so only HIGH-confidence page signals produce defect findings.
- Added mandatory evidence extraction for each signal finding (`evidence_text` from the first 1–2 lines + top screenshot reference).
- Added limited `MICRO_CLUSTER` generation for repeated HIGH-confidence signals on 2+ routes.
- Simplified decision and human-report outputs so they focus on one strongest problem and 1–2 supporting examples.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry script unchanged: `agents/site_auditor_v2/agent.ps1`
- Route discovery logic unchanged (no crawler/discovery edits).
- Screenshot engine unchanged (`agents/site_auditor_v2/tools/capture_visuals.mjs` untouched).
- Ownership logic preserved (`Get-OwnershipMode` and ownership action selection still in place).
- Confidence output remains in `RUN_REPORT` with tightened signal-specific HIGH/LOW gating for findings.

## Risks/blockers
- Stricter HIGH-only filtering may reduce findings volume on sparse or weakly captured pages by design.
- `MICRO_CLUSTER` findings are intentionally limited and currently generated only when the same HIGH signal repeats on at least 2 routes.
- If top screenshots or first-screen text snippets are missing, candidate signals are ignored rather than downgraded into noisy findings.
- Rollback plan: revert commit `feat(site_auditor_v2): add hardened signals and micro-cluster layer` to restore previous multi-signal findings behavior.
