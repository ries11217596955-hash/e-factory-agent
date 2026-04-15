## Summary
- Updated the workflow validation semantics in `.github/workflows/site-auditor-fixed-list.yml` to fail only on agent runtime breakage, not on negative audit findings.
- Removed fail-gating tied to `RUN_REPORT` generic `FAIL` status parsing and retained report discovery/visibility logging.
- Added explicit runtime fail detection for `RUN_REPORT.json` when either `status == RUNTIME_FAIL` or `execution == CRASH`.
- Preserved artifact discovery behavior across `audit_bundle`, `outbox`, and `reports` so CI still verifies report presence.
- Kept audit-result visibility as informational only, allowing bad-site findings (`audit_result` FAIL) without failing the job.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
None.

## Current entrypoints/paths
- Workflow entry remains `.github/workflows/site-auditor-fixed-list.yml` (`site-audit` job, `Validate agent result` step).
- Validation searches these report directories:
  - `agents/gh_batch/site_auditor_cloud/audit_bundle`
  - `agents/gh_batch/site_auditor_cloud/outbox`
  - `agents/gh_batch/site_auditor_cloud/reports`
- Validation considers these report files:
  - `audit_result.json`
  - `RUN_REPORT.json`
- Runtime fail gate now triggers only when `RUN_REPORT.json` contains:
  - `"status": "RUNTIME_FAIL"`, or
  - `"execution": "CRASH"`.

## Risks/blockers
- Runtime-fail detection uses pattern matching (`grep`) against JSON text; schema/key casing changes could reduce detection accuracy.
- End-to-end verification of workflow outcome still requires GitHub Actions execution because local runner parity is not available in this environment.
