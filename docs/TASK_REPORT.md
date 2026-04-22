## Summary
Aligned LINK run artifact publication with `RUN_REPORT` truth by making `produced_artifacts` runtime-accurate, adding truthful empty-target handoff guidance, and enforcing pre-upload artifact assertions in workflow.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml`
- Published bundle source: `site_auditor_v2_artifact_bundle/` (created at workflow runtime)
- `RUN_REPORT.produced_artifacts` now reflects only artifacts generated in the current run
- `operator_handoff` now avoids `problem_targets` page-inspection directives when `problem_targets` is empty

## Risks/blockers
- None.
