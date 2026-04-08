## Summary
- Updated `site-auditor-fixed-list` trigger model to support all three required entrypoints: `workflow_dispatch`, `push` on `main`, and `workflow_run` completion from `Safe Auto Merge`.
- Removed restrictive `push.paths` filtering so valid post-merge runs are not skipped when merge commits do not touch auditor workflow paths.
- Added `workflow_run` success + `main` branch guards at the job level to ensure Safe Auto Merge-triggered runs only execute for successful mainline merges.
- Added workflow-level concurrency controls keyed by event + commit SHA to reduce duplicate/noisy overlap when `push` and `workflow_run` may both target the same post-merge commit.
- Preserved the existing SITE_AUDITOR execution and artifact publishing flow (same runner path and `audit-output` artifact upload pattern), keeping the current bundle-oriented operator output path unchanged.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoints:
  - `workflow_dispatch` (manual operator runs)
  - `push` on `main` (manual merge / normal push post-merge path)
  - `workflow_run` on completed `Safe Auto Merge` runs (auto-merge post-merge path)
- `workflow_run` execution guards:
  - upstream workflow conclusion must be `success`
  - upstream `head_branch` must be `main`
- SITE_AUDITOR execution path remains:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
- Published artifact remains:
  - `audit-output` from
    - `agents/gh_batch/site_auditor_cloud/outbox/**`
    - `agents/gh_batch/site_auditor_cloud/reports/**`

## Risks/blockers
- `workflow_run` and `push` can still both start near-simultaneously in edge timing windows; concurrency now minimizes in-flight duplication per event/SHA grouping, but final behavior still depends on GitHub Actions event delivery timing.
- End-to-end trigger verification requires GitHub-hosted runtime events (actual `push`/`Safe Auto Merge` completion); local environment can validate YAML syntax/structure but cannot simulate full GitHub event dispatch semantics.
