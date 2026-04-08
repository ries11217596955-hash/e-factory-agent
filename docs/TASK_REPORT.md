## Summary
Implemented a temporary TRI-AUDIT BUNDLE mode for `SITE_AUDITOR` workflow runs so one run produces one combined `audit_bundle` artifact with REPO, ZIP, and URL subruns. The orchestration reuses existing single-mode auditor logic and layers URL discovery + SKIPPED semantics around it.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
  - Switched workflow execution to `run_bundle.ps1` temporary bundle orchestrator.
  - Preserved `push` on `main` and `workflow_dispatch` entrypoints.
  - Kept target repo checkout + Node/Playwright setup; uploads combined `audit_bundle/**` artifact.
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
  - New temporary tri-mode orchestrator.
  - Runs REPO/ZIP/URL subruns sequentially using existing `run.ps1` mode execution.
  - Adds SKIPPED behavior for missing ZIP / missing URL / missing repo path.
  - Resolves URL by deterministic priority: explicit input, default env, discovered repo URL, discovered ZIP URL, none.
  - Captures per-mode artifacts under `audit_bundle/repo|zip|url` and writes top-level `REPORT.txt` + `master_summary.json`.
- `agents/gh_batch/site_auditor_cloud/lib/url_discovery.ps1`
  - New conservative URL discovery helper for repo/zip roots.
  - Scans likely config/content files only, extracts URL candidates, deterministically selects best URL, and records alternatives/warnings.

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-fixed-list.yml`.
- Bundle orchestrator: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- URL discovery helper: `agents/gh_batch/site_auditor_cloud/lib/url_discovery.ps1`.
- Published combined artifact root: `agents/gh_batch/site_auditor_cloud/audit_bundle/`.

## Risks/blockers
- `actions/checkout` of target repo uses `GH_BATCH_PAT`; if unavailable/invalid, REPO subrun will be SKIPPED in bundle output.
- ZIP subrun requires payload in `agents/gh_batch/site_auditor_cloud/input/inbox`; absent payload intentionally reports SKIPPED.
- URL discovery is intentionally conservative and may miss URLs embedded in uncommon file locations/formats.
- This is temporary additive orchestration; single-mode internals are reused and not deeply refactored.
