## Summary
- Rebuilt `Build-DecisionLayer` with deterministic shape normalization for list/text/object contracts in the decision-core path.
- Repaired `Build-ProductCloseoutClassification` to normalize inbound decision fields and emit strict output shapes (`checks` object array, `evidence` string array).
- Tightened `Convert-ToProductStatus` to consume normalized closeout data and return only the required ordered status fields.
- Preserved existing report/output layer behavior and avoided changes outside the decision-core trio.
- Kept runtime semantics outside the trio unchanged while removing ambiguous mixed-shape branching in DECISION_BUILD.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry script remains `agents/gh_batch/site_auditor_cloud/agent.ps1`.
- Decision-core changes are limited to `Build-DecisionLayer`, `Build-ProductCloseoutClassification`, and `Convert-ToProductStatus`.

## Risks/blockers
- `pwsh` is unavailable in this container, so full runtime execution of the DECISION_BUILD pipeline could not be performed here.
- Runtime outcomes (stage advancement and populated source/live/page_quality data) require execution in the target environment with real inputs.
