# SITE_AUDITOR_AGENT — v2.1 clean baseline

This pack is intended for the `e-factory-agent` repo.

## Current status

`SITE_AUDITOR_AGENT v2.1` = `baseline_workable`

Validated runtime path on target PC:
- loading config
- resolving token
- loading audit files
- fetching repository via GitHub API ZIP download
- building inventory
- semantic audit
- broken links audit
- screenshots (optional, browser-dependent)
- packaging one ZIP report into `outbox`

## Delivery model

Agent is delivered as a ZIP package.

Install contract:
1. unzip package
2. put GitHub token into `.state/github_token.txt`
3. run `run.ps1`
4. collect report from `outbox`

## Package in this repo

Use:
- `SITE_AUDITOR_AGENT_v2_1_CLEAN.zip`

Previous package may be kept only as legacy reference until repo cleanup.

## Current capabilities

- GitHub repository download through GitHub API ZIP (token-first, no git dependency)
- inventory build for site source files
- semantic issues detection
- broken links scan
- orphan pages detection
- optional live screenshots through installed browser
- one ZIP audit pack output

## Current known limitations

- audit scope is still noisy and includes some non-publishable markdown files
- screenshot step may write browser stderr noise while still producing PNG files
- no Eleventy collection validation yet
- no full render graph / architecture graph yet
