## Summary
- Optimized SITE_AUDITOR startup in `.github/workflows/site-auditor-fixed-list.yml` by removing unconditional Playwright browser reinstall behavior and switching to conditional installation.
- Added Playwright cache restore/save via `actions/cache@v4` using `~/.cache/ms-playwright` with key `playwright-${{ runner.os }}`.
- Added filesystem presence check for Playwright browser cache before installation; install now runs only when cache is empty/missing.
- Replaced heavy browser install path with lightweight `npx playwright install chromium` (without apt-style full dependency reinstall) to reduce setup overhead.
- Added explicit startup telemetry logs: `PLAYWRIGHT_INSTALL_SKIPPED` and `PLAYWRIGHT_INSTALL_DONE`.
- Runtime impact expectation:
  - Before: setup was dominated by repeated Playwright browser install/deps work (often several minutes).
  - After: cached runs should skip Playwright install (setup target <30s), with audit phase target <90s and total target <2 minutes.

## Changed files
- `.github/workflows/site-auditor-fixed-list.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Workflow entrypoint: `.github/workflows/site-auditor-fixed-list.yml`
- Playwright cache path: `~/.cache/ms-playwright`
- Cache key: `playwright-${{ runner.os }}`
- Conditional install command: `npx playwright install chromium`
- Install skip condition: cached Playwright directory exists and contains at least one browser folder/file.

## Risks/blockers
- First run on a fresh runner (cold cache) still performs Playwright install and can exceed the fast-path setup target; subsequent runs are expected to benefit from cache.
- Cache key is OS-wide (`playwright-${{ runner.os }}`) and not version-pinned; if Playwright version changes significantly, stale cache behavior may require key bumping.
- This change intentionally does not modify `run_bundle.ps1`, Phase C, or repo binding logic per scope restrictions.
