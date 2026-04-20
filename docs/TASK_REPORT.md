## Summary
- Repaired the proven maturity_readiness collection-shape defect in `Build-MaturityReadinessLayer` by making missing input counting array-shape safe.
- Hardened only the same-family count expression in-scope of `Build-MaturityReadinessLayer`; no contradiction logic or entrypoints were changed.
- Preserved existing maturity classification and confidence semantics; only collection safety logic changed.
- Executed the forensic runner after patching to validate that `maturity_readiness_build` no longer fails with `.Count` property errors.
- Kept the change bounded to the allowed module and task report file.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/decision_diagnosis.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Repaired module path: `agents/gh_batch/site_auditor_cloud/modules/decision_diagnosis.ps1`
- Forensic harness path (unchanged): `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- Snapshot input path (unchanged): `agents/gh_batch/site_auditor_cloud/tools/decision_build_snapshot.diagnostic_cloudlineage.json`
- Production entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`

## Risks/blockers
- Forensic validation depends on local `pwsh` availability and snapshot fidelity.
- If future failures occur, they may appear in downstream nodes with different defect classes and require separate bounded repairs.
