# Final Root Closeout

Date: 2026-04-07 (UTC)

## Moved folders

### Moved to `_quarantine/root_legacy/`
- `done/`
- `failed/`
- `logs/`
- `runtime/`
- `inbox/`
- `good/`
- `releases/`
- `15a/`
- `20c/`
- `21f/`
- `513/`
- `56a/`
- `5eb/`
- `64d/`
- `782/`
- `a34/`
- `c7b/`
- `dc9/`
- `agent/`
- `.github/`

### Moved to `_foreign/webops/`
- `posts/`
- `hubs/`
- `templates/`
- `page/`
- `partials/`
- `src/`
- `_includes/`
- `about/`
- `tags/`

## Moved files

### Moved to `docs/legacy_root_notes/`
- `APPLY_NOTE.md`
- `APPLY_PHASE2.txt`
- `DELETE_ROOT_FILES.txt`
- `PHASE3_DELETE_LIST.txt`
- `README.txt`
- `README_APPLY.txt`
- `README_APPLY_PHASE3.txt`
- `batch_result_batch-002.txt`
- `robots.txt`
- `sitemap.xml.njk`
- `index.md`

### Moved to `_quarantine/root_legacy/`
- `AGENT_VERSION.json`

## Final root tree

- `.git/`
- `.gitignore`
- `README.md`
- `_foreign/`
- `_quarantine/`
- `agents/`
- `config/`
- `docs/`
- `scripts/`
- `tests/`

## Remaining uncertainties

- `c76/` was listed as an example legacy folder but was not present at root during this closeout.
- `releases/` was treated as legacy package storage and quarantined to satisfy canonical root constraints.
- `.github/` is non-canonical for this root policy and was quarantined; CI workflows are preserved but no longer at root.

## Risks / blockers

- If CI depends on root `.github/workflows`, pipeline triggers will not run until workflows are restored/migrated.
- If any external automation expects root-level `releases/` or legacy web files, those integrations must be repointed to `_quarantine/root_legacy/` or `_foreign/webops/`.
- No deletions were performed; only moves.

## Correction note (2026-04-07 UTC)

- `.github/workflows/` is an active infrastructure path and must remain at repository root for GitHub Actions to trigger correctly.
- Three workflow files were restored to root `.github/workflows/` after the cleanup quarantine step.
