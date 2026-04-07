# Workflow Restore Note

Date: 2026-04-07 (UTC)

## Restored files

- `.github/workflows/gh-batch.yml`
- `.github/workflows/site-auditor-fetch-trace.yml`
- `.github/workflows/site-auditor-fixed-list.yml`

## Why they were restored

These workflows were unintentionally moved during root cleanup. GitHub Actions only discovers repository workflows from the root `.github/workflows/` path.

## Workflow root path confirmation

The active workflow root path is:

- `.github/workflows/`
