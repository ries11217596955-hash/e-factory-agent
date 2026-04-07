## Summary
Updated the fixed-list GitHub Actions workflow to prepare live-audit runtime dependencies (Node.js, npm install, and Playwright browser install) for every mode that invokes live audit routing: manual `REPO`, manual `URL`, and push-triggered `ZIP`. Kept `SITE_AUDITOR` routing contract, `TARGET_REPO_PATH`, and artifact upload paths unchanged.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-fixed-list.yml`
- SITE_AUDITOR invocation step: `Run SITE_AUDITOR` in the same workflow
- Manual REPO checkout path: `${{ github.workspace }}/target_repo`
- TARGET_REPO_PATH passed to auditor: `${{ github.workspace }}/target_repo`
- Live-audit dependency preparation now runs on:
  - `workflow_dispatch` with `audit_mode=REPO`
  - `workflow_dispatch` with `audit_mode=URL`
  - `push` trigger (`FORCE_MODE=ZIP`)
- Artifact upload paths (unchanged):
  - `agents/gh_batch/site_auditor_cloud/outbox/**`
  - `agents/gh_batch/site_auditor_cloud/reports/**`

## Risks/blockers
- Dependency setup now also runs on push-triggered ZIP audits, which increases run time for push executions compared with URL-only setup.
- `DEFAULT_BASE_URL` remains `https://automation-kb.pages.dev`; if deployment URL changes, operators must pass `base_url` in manual runs or update workflow defaults.
