## Summary
- Root cause: `run_bundle.ps1` could invoke REPO subrun without a verified bound repo path, so REPO could execute with an unbound/invalid target and produce non-deterministic downstream assembly behavior.
- Added deterministic REPO binding gate in bundle execution: explicit `TARGET_REPO_PATH` validation now emits `REPO_BINDING_OK path=<...>` or `REPO_BINDING_FAIL reason=<...>` and returns a normalized REPO FAIL object when invalid.
- Normalized subrun contract through `New-ModeResult` so assembly receives a consistent object shape and REPO results always include the strict fields (`mode`, `executed`, `status`, `reason`, `exit_code`, `repo_root`, `target_repo_bound`, `artifacts_present`, `outbox_path`, `reports_path`).
- Added assembly input validation (`Test-ModeResultShape`) and malformed-input fallback conversion with `ASSEMBLY_INPUT_OK` logging to prevent mixed-object aggregation and avoid type mismatch crashes.
- Updated workflow target checkout condition so bundle/manual REPO runs explicitly bind `${{ github.workspace }}/target_repo` before REPO mode execution.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle entrypoint: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- REPO binding input: environment variable `TARGET_REPO_PATH`
- Workflow binding producer: `.github/workflows/site-auditor-fixed-list.yml`
  - Checkout target repo into `target_repo`
  - Export `TARGET_REPO_PATH: ${{ github.workspace }}/target_repo` for bundle and single-mode runs

## Risks/blockers
- If `target_repo` checkout fails (e.g., token/repo access issue), REPO subrun now deterministically returns FAIL (by design) instead of attempting to proceed.
- Assembly now enforces mode-result shape and converts malformed items into deterministic FAIL records; this is safer, but may expose previously hidden producer bugs.
- ZIP/URL modes remain stage-skipped by current activation policy and were not reactivated in this change.

### Root cause
- REPO execution path lacked a hard preflight bind check in `run_bundle.ps1`; execution could continue without guaranteed `TARGET_REPO_PATH` validity.

### Binding path before/after
- Before:
  - Bundle workflow exported `TARGET_REPO_PATH`, but target repo checkout was only conditional for manual REPO single-mode.
  - Bundle REPO path could be absent on push/manual-bundle runs.
- After:
  - Workflow now checks out target repo for push bundle, manual bundle, and manual REPO single-mode.
  - `run_bundle.ps1` validates `TARGET_REPO_PATH` exists and is a directory before invoking REPO subrun.

### Result object schema
- REPO result object (strict):
  - `mode` = `"REPO"`
  - `executed` = bool
  - `status` = `"OK" | "PARTIAL" | "FAIL"`
  - `reason` = string
  - `exit_code` = int
  - `repo_root` = string|null
  - `target_repo_bound` = bool
  - `artifacts_present` = bool
  - `outbox_path` = string|null
  - `reports_path` = string|null
