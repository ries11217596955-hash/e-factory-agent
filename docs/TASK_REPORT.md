## Summary
- Fixed a manifest return-stage type mismatch in `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` by introducing strict normalization for `repo`, `zip`, and `url` result blocks.
- Added `Normalize-Result` to enforce deterministic `{ status, reason }` hashtable shape for each manifest component before manifest assembly.
- Rebuilt final manifest using strict schema keys (`overall`, `repo`, `zip`, `url`) and explicit string casting.
- Added a final JSON round-trip stabilization guard (`ConvertTo-Json | ConvertFrom-Json`) before return to avoid runtime type mismatch at return stage.
- Added manifest success telemetry log `MANIFEST_NORMALIZED_OK` and switched final output to `return $manifest` while preserving `$LASTEXITCODE`.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle runner entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Fix location in file: finalization section after `Invoke-WritingStage` and before script termination/return.
- Added normalization helper: `Normalize-Result` in `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.

## Risks/blockers
- Final guard intentionally converts the hashtable manifest into a deserialized object (`PSCustomObject`) to stabilize return types; downstream callers that require literal hashtable semantics may need to consume properties rather than hashtable methods.
- Existing behavior changed from `exit $exitCode` to returning manifest object with `$LASTEXITCODE` set; callers depending on direct process termination semantics should validate integration behavior.
