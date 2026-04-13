# TASK_REPORT

## Summary
- Replaced unsafe `.Count` usages in DECISION_BUILD functions with null-safe collection length evaluation using `@(...)` and null filtering.
- Updated conditional Count checks to deterministic expressions like `@($var).Where({ $_ -ne $null }).Count`.
- Updated direct Count reads/embeds to safe expressions like `(@($var) | Where-Object { $_ -ne $null }).Count`.
- Kept DECISION_BUILD flow and branching unchanged; only Count access mechanics were updated.
- Preserved output contract behavior for contradiction, diagnosis, and product closeout generation paths.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoints unchanged:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- DECISION_BUILD Count safety updates were applied in:
  - `Build-ContradictionLayer`
  - `Build-SiteDiagnosisLayer`
  - `Build-ProductCloseoutClassification`
  - `Build-DecisionLayer`

## Risks/blockers
- Full runtime verification (DECISION_BUILD completion and artifact generation) depends on running the PowerShell pipeline with task inputs.
- If this environment lacks `pwsh` or required input fixtures, validation is limited to static Count-usage checks.
