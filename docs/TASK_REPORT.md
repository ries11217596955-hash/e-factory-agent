## Summary
- Downgraded `primary_targets` in `Build-DecisionLayer` missing-input handling from a blocking P0 to a warning message.
- Preserved P0 behavior for all other missing inputs.
- Updated decision-level final status candidate logic to ignore `primary_targets` as a blocking missing input.
- Updated run-level status determination to ignore `primary_targets` as a blocking missing input.
- Kept SOURCE/LIVE validation and required-input enforcement unchanged.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entry point unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`
- Decision logic updated in `Build-DecisionLayer` missing-input processing and candidate status evaluation.
- Final run status evaluation updated in the main execution flow after `Build-DecisionLayer`.

## Risks/blockers
- Validation performed via static inspection only; full runtime confirmation of REPO subrun behavior depends on executing the pipeline with a payload where `primary_targets` is omitted.
