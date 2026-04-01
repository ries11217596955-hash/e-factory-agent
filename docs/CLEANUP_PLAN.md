# Cleanup Plan

## Phase 1 — establish source of truth
Done in this patch:
- canonical folders for active agents created
- active package contents materialized under `agents/`
- root README and repo manifest rewritten

## Phase 2 — root cleanup
Next cleanup commit should:
- remove old ZIP releases from repo root
- remove misleading duplicate root entrypoints
- remove or repurpose placeholder scaffold folders

## Phase 3 — optional release discipline
If releases remain in repo:
- store them only under `releases/gh_batch/` and `releases/site_auditor_agent/`
- add one manifest per release batch
- stop mixing releases with source
