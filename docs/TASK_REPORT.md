## Summary
- Restored screenshot propagation for REPO subrun artifacts by detecting PNG files from `audit_bundle/repo/reports` and `audit_bundle/repo/outbox` during bundle processing.
- Added deterministic screenshot manifest assembly so `bundle_status.repo.artifacts` is populated with `bundle_artifacts/<name>.png` entries.
- Added writing-stage copy flow that materializes screenshots into `audit_bundle/bundle_artifacts/` for artifact packaging.
- Updated `REPORT.txt` generation to include a `SCREENSHOTS` section listing captured screenshot filenames.
- Added safe no-screenshot behavior: report now writes `No screenshots captured` without failing the bundle.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Bundle orchestrator: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Screenshot source scan roots: `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/reports` and `agents/gh_batch/site_auditor_cloud/audit_bundle/repo/outbox`
- Screenshot bundle destination: `agents/gh_batch/site_auditor_cloud/audit_bundle/bundle_artifacts`
- Report output: `agents/gh_batch/site_auditor_cloud/audit_bundle/REPORT.txt`
- Artifact upload path (already configured wildcard): `.github/workflows/site-auditor-fixed-list.yml` uploads `agents/gh_batch/site_auditor_cloud/audit_bundle/**`

## Risks/blockers
- If two screenshots share the same filename across `reports/` and `outbox/`, names are de-duplicated using a numeric suffix (for example `screen.png`, `screen-2.png`); downstream tooling should not assume original duplicates remain unchanged.
- This change intentionally does not modify workflow files due scope and protected-path constraints; inclusion in artifact ZIP relies on existing `audit_bundle/**` upload wildcard.
- Flow remains non-fatal for missing screenshots by design.

### Artifact flow (before/after)
- Before: REPO screenshots could exist in `reports/` or `outbox/` but were not copied into bundle output, not enumerated in bundle assembly metadata, and not listed in `REPORT.txt`.
- After: REPO screenshots are detected -> manifest created -> copied into `audit_bundle/bundle_artifacts/` -> registered in `bundle_status.repo.artifacts` -> listed in `REPORT.txt` under `SCREENSHOTS`.

### Paths used
- Input scan:
  - `audit_bundle/repo/reports/*.png`
  - `audit_bundle/repo/outbox/*.png`
- Output copy:
  - `audit_bundle/bundle_artifacts/*.png`
- Metadata/report:
  - `audit_bundle/audit_bundle_summary.json` (`repo.artifacts`)
  - `audit_bundle/REPORT.txt` (`SCREENSHOTS` section)

### Example output
- `audit_bundle_summary.json`:
  - `"repo": { "artifacts": ["bundle_artifacts/screenshot_home.png", "bundle_artifacts/screenshot_checkout-2.png"] }`
- `REPORT.txt`:
  - `SCREENSHOTS`
  - `-----------`
  - `- screenshot_home.png`
  - `- screenshot_checkout-2.png`
  - *(or `No screenshots captured` when absent)*
