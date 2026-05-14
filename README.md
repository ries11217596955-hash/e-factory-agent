# E-Factory Agent Repo

## Purpose
Canonical source repository for the active AGENTOPS execution line.

## Active line
- `SITE_AUDITOR_V3`
- source root: `agents/site_auditor_v3/`
- operator surface: `.github/workflows/site-auditor-v3.yml`

## Current product contour
The agent is a universal audit engine.
Current website/site runs are one execution lane, not the total product boundary.

Current proven orchestration model:
- START = open a scoped audit session and process the first bounded batch
- NEXT = restore the matching open session and process one next batch
- FULL = start or resume a session and continue until completion
- one unified artifact = report + map + session state + ledger truth

## Canonical repo layout
- `agents/site_auditor_v3/` — active source, contracts, docs, tests, tools
- `.github/workflows/` — operator workflow entrypoint
- `.codex/` — controlled patch-execution configuration
- `.gitignore`
- `AGENTS.md`
- `README.md`

## Repo hygiene rules
1. Runtime outputs, session state, deliverables, caches and local diagnostics do not live in git.
2. Historical audit snapshots and one-off closeout files do not remain in repo root.
3. Current operator truth must not reference removed V2-era paths or placeholder directories.
4. Agent capability truth belongs in generated artifacts and current V3 docs, not in stale task-report leftovers.
