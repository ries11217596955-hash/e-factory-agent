# APPLY NOTE — e-factory-agent

CommitId: COMMIT-2026-03-16-SITE-AUDITOR-V2_1-CLEAN-BASELINE
CoreRev: KERNEL.AGENTOPS + AGENT.FETCH.GITHUB_API_ZIP.TOKEN_FIRST v1.0

## What to update in repo

Replace / add these files in repo root:
- `AGENT_VERSION.json`
- `README.md`
- `APPLY_NOTE.md`
- `SITE_AUDITOR_AGENT_v2_1_CLEAN.zip`

## Agent line status

Line: `SITE_AUDITOR_AGENT`
Status: `BASELINE_WORKABLE`

## Validated runtime path

- config -> OK
- token -> OK
- module load -> OK
- GitHub API ZIP fetch -> OK
- inventory -> OK
- semantic audit -> OK
- broken links audit -> OK
- screenshots -> OK (browser-noise tolerated)
- packaging -> OK

## Current limitations to keep explicit

- scope filtering still noisy
- screenshots are browser-dependent
- line is workable baseline, not final deep-audit release
