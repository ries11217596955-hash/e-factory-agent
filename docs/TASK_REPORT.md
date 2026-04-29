## Summary
- Updated ACTION_SUMMARY final status resolution to use a single truth path aligned to run failure and finding counts.
- Enforced precedence: FAIL (runFailed) → DEFECT → LIMITATION_ONLY → CLEAN.
- Locked `status` to `status_label` output so FAIL can never pair with CLEAN in the same summary object.
- Kept scope limited to report-layer status computation only.
- Did not modify entrypoints, workflows, artifact paths, or agent runtime flow.

## Changed files
- `agents/site_auditor_v2/modules/report_layer.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains: `agents/site_auditor_v2/agent.ps1`.
- Report-layer status logic remains in: `agents/site_auditor_v2/modules/report_layer.ps1` (`New-ActionSummaryFromDecision`).
- No path, routing, or artifact write location changes were introduced.

## Risks/blockers
- Low risk: change is constrained to status derivation logic and preserves existing fields.
- No blocker identified for REPORT_LAYER consistency checks.
