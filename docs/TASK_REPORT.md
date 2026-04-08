## Summary
- Implemented staged TRI-AUDIT activation in `run_bundle.ps1` so only REPO executes in bundle mode.
- Kept the 3-mode TRI-AUDIT contract intact (`REPO`, `ZIP`, `URL`) while forcing ZIP and URL to deterministic SKIPPED results.
- Added explicit skip reason `SKIPPED_BY_STAGE_ACTIVATION` for non-active bundle modes to keep output honest and operator-readable.
- Ensured ZIP/URL bundle paths are created and reported without invoking `run.ps1`, preventing ZIP/URL runtime failures from crashing bundle execution.
- Left manual single-mode execution behavior unchanged; CI/main bundle path remains TRI-AUDIT but now runs REPO-only by stage design.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle entrypoint (staged TRI-AUDIT, REPO active):
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Manual single-mode entrypoint (explicit operator path, unchanged):
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
- CI workflow invoking bundle path:
  - `.github/workflows/site-auditor-fixed-list.yml`

## Risks/blockers
- Local environment may not have `pwsh`, so full runtime validation of the PowerShell bundle path may require GitHub Actions or a PowerShell-enabled runner.
- This task intentionally does not stabilize ZIP/URL runtime internals; those modes are explicitly staged as SKIPPED by design until later activation.
