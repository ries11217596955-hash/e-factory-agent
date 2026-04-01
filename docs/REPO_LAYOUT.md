# Agent Repo Layout

## Canonical directories
- `agents/gh_batch/`
- `agents/site_auditor_agent/`
- `releases/`
- `docs/`

## Intent
This repo should behave as a source repo, not as a dump of historical ZIP packages.

## Rules
1. Put active source files under `agents/` only.
2. Put future release ZIPs under `releases/<agent>/` only if keeping them in git is truly necessary.
3. Do not keep multiple root-level copies of the same entrypoint.
4. Do not infer runtime success from packaging or presence of files.
5. Keep runtime outputs, tokens, logs and inbox/outbox artifacts outside git or ignored.

## Transitional note
This patch establishes the target structure. Root-level legacy ZIP files should be removed in a follow-up cleanup commit.
