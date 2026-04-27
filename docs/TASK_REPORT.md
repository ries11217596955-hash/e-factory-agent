## Summary
- Updated `Resolve-MinimalDecision` to accept `LINK_SUMMARY` when either `status` or `status_code` is present.
- Added fallback derivation of link status from `status_code` when `status` is missing: `200-399 => OK`, otherwise `FAIL`.
- Preserved failure behavior when both `status` and `status_code` are missing.

## Changed files
- agents/site_auditor_v2/lib/decision.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator (unchanged): `agents/site_auditor_v2/agent.ps1`
- Decision/report validation logic (updated): `agents/site_auditor_v2/lib/decision.ps1`

## Risks/blockers
- Full end-to-end SITE_AUDITOR_V2 workflow was not executed in this environment.
- Runtime verification is limited because PowerShell (`pwsh`) is unavailable in this container; changes were validated by code inspection and diff review.
