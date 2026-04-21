## Summary
- Task: SITE_AUDITOR repair batch for post-`PAGE_QUALITY_BUILD` failure at the final operator output contract boundary.
- Exact failing node identified from bundle lineage: `FINAL_CONTRACT_BUILD / Convert-ToHashtableSafe / singleton_contract_projection`.
- Located boundary in `agents/gh_batch/site_auditor_cloud/modules/util_convert.ps1` at `Convert-ToHashtableSafe`, which is used when final report/contract nodes are normalized before JSON serialization.
- Fixed type/shape mismatch by normalizing all dictionaries (including empty dictionaries) directly to ordered hashtables instead of falling through to `__raw` wrapping.
- Added minimal serialization hardening for enumerable inputs: empty enumerable now resolves to `{}` and singleton enumerable still projects recursively to a single normalized object.

## Changed files
- `agents/gh_batch/site_auditor_cloud/modules/util_convert.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- Repaired module boundary: `agents/gh_batch/site_auditor_cloud/modules/util_convert.ps1` (`Convert-ToHashtableSafe`).

## Risks/blockers
- Runtime verification is blocked in this container because `pwsh`/`powershell` are unavailable, so full pipeline completion could not be executed locally.
- Next operator run should confirm that execution now advances through final contract/report emission beyond `FINAL_CONTRACT_BUILD / Convert-ToHashtableSafe / singleton_contract_projection`.
