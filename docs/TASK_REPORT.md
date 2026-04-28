## Summary
- Fixed `ACTION_SUMMARY` truth alignment by deriving `effectiveDefectCount` from both explicit defect count and synthesized findings list size.
- Prevented contradictory clean status when findings exist by using `effectiveDefectCount` for `status`, `finding_count`, and `reason`.
- Forced defect-context action targeting: if defect evidence exists and the top action is blank or route-expansion-only text, `ACTION_SUMMARY.actions[0].action` now pivots to broken-route investigation/repair guidance.
- Kept consistency guard strictness intact (no guard removal or weakening); this is a targeted report-layer-only fix.
- Scope stayed within allowed files and reporting requirements.

## Changed files
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Action summary generation entrypoint remains `New-ActionSummaryFromDecision` in `agents/site_auditor_v2/modules/report_layer.ps1`.
- Failure classification flow/entrypoints are unchanged in this task; only summary truth mapping inputs were corrected in report layer output generation.
- Output/report artifact paths remain unchanged (`ACTION_SUMMARY.json`, `RUN_REPORT.json`, `failure_summary.json`).

## Risks/blockers
- Validation here was limited to static checks/diff inspection in this environment; no full live SITE_AUDITOR_V2 execution artifact replay was run.
- If upstream synthesis supplies an empty `SortedFindings` despite true broken-route evidence elsewhere, this fix cannot infer unseen findings and depends on upstream truth artifacts being wired as intended.
