## Summary
Manual repair pack for SITE_AUDITOR_V2 after runpack 51. Root causes addressed: REPORT_LAYER still used pre-normalization finding collections after the finding contract gate, and ACTION_SUMMARY generation used unsafe report-layer shapes/writer path that could fail before `REPORT_LAYER: HUMAN_PAYLOAD_START` with `Argument types do not match`.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/report_contract.ps1
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Primary entrypoint: `agents/site_auditor_v2/agent.ps1`
- Contract module: `agents/site_auditor_v2/modules/report_contract.ps1`
- Report layer module: `agents/site_auditor_v2/modules/report_layer.ps1`
- Diagnostic artifact: `REPORT_CONTRACT_DIAG.json`

## Root causes fixed
1. After `Normalize-FindingContract`, `agent.ps1` reassigned `$report.findings` but kept `$allFindings`, `$defectFindings`, and `$limitationFindings` pointing to the old pre-contract shapes. The report layer then continued using stale/non-normalized collections.
2. `REPORT_CONTRACT_DIAG.json` showed `evidence.evidence_refs` could still serialize as null; the contract module now returns a new normalized finding object with explicit `evidence.evidence_refs` array.
3. `New-ActionSummaryFromDecision` and the ACTION_SUMMARY write corridor were still sensitive to PowerShell collection/object shape. The action summary is now materialized through the same bounded value converter before write, and new markers were added around that corridor.

## Runtime verification
- Not executed in this environment.
- Operator validation should confirm:
  - `REPORT_LAYER: ACTION_SUMMARY_READY`
  - `REPORT_LAYER: ACTION_SUMMARY_WRITTEN`
  - `REPORT_LAYER: HUMAN_PAYLOAD_START`
  - `OUTPUT: WRITE_DONE`
  - `RUN_REPORT.status` is not `FAIL` unless a later real blocker appears.
