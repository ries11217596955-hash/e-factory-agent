## Summary
- Added a real SITE_AUDITOR PowerShell preflight validator script that parses required `.ps1` files with PowerShell parser APIs and fails on parser errors.
- Added a token misuse guard that fails on standalone `and` / `or` identifiers where PowerShell expects `-and` / `-or`.
- Added a dedicated GitHub Actions workflow (`SITE_AUDITOR PowerShell Preflight`) that runs `pwsh` validation for PRs that touch SITE_AUDITOR PowerShell files.
- Updated Safe Auto Merge so PRs changing `agents/gh_batch/site_auditor_cloud/*.ps1` must have a successful `validate-powershell` check before auto-merge is allowed.
- Validator output now includes per-file syntax/token status plus structured JSON summary for machine and operator review.

## Changed files
- `.github/workflows/site-auditor-powershell-preflight.yml`
- `.github/workflows/safe-auto-merge.yml`
- `agents/gh_batch/site_auditor_cloud/lib/validate-powershell-preflight.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- CI validator workflow:
  - `.github/workflows/site-auditor-powershell-preflight.yml`
- Safe auto-merge gate integration:
  - `.github/workflows/safe-auto-merge.yml`
- PowerShell validator script:
  - `agents/gh_batch/site_auditor_cloud/lib/validate-powershell-preflight.ps1`
- Validated SITE_AUDITOR script contour:
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/lib/*.ps1`

## Risks/blockers
- Local container does not include `pwsh`, so execution of the validator was not runnable in this environment; runtime verification depends on GitHub Actions runner execution.
- Branch protection settings are repository-level configuration outside this codebase; this task enforces the gate via workflow checks and Safe Auto Merge logic within repository-controlled automation.
