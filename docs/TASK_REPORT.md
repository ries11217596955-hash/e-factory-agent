## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)

## Summary
- Applied a PowerShell 5.1 compatibility hotfix in `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` with no logic expansion.
- Removed invalid inline `if (...) { ... } else { ... }` expressions from `New-ModeResult` argument positions in the synthesized REPO PARTIAL path by precomputing values first.
- Replaced null-coalescing operator usage (`??`) in `Normalize-Result` with explicit null checks compatible with Windows PowerShell 5.1.
- Kept behavior identical: same status/reason coercion and same outbox/reports path decisions.

## Root cause
- The REPO PARTIAL synthesis used inline `if` script blocks directly in command argument positions:
  - `-OutboxPath (if (...) { ... } else { ... })`
  - `-ReportsPath (if (...) { ... } else { ... })`
  This can fail at runtime with `The term 'if' is not recognized...` in this invocation style.
- `Normalize-Result` used PowerShell null-coalescing operator `??`, which is not available in Windows PowerShell 5.1:
  - `$status = [string]($statusRaw ?? '')`
  - `$reason = [string]($reasonRaw ?? '')`

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- No changes to workflows, runtime flow architecture, Playwright behavior, `agent.ps1`, or report design.

## Exact edited blocks
- `Invoke-AssemblyStage` synthesized REPO PARTIAL block:
  - Added precomputed locals:
    - `$repoOutboxPath = if ($repoEvidence.has_outbox) { $repoEvidence.outbox_dir } else { $null }`
    - `$repoReportsPath = if ($repoEvidence.has_reports) { $repoEvidence.reports_dir } else { $null }`
  - Updated `New-ModeResult` call to pass:
    - `-OutboxPath $repoOutboxPath`
    - `-ReportsPath $repoReportsPath`
- `Normalize-Result` null-safe coercion:
  - Replaced `??` expressions with explicit null checks:
    - `$status = if ($null -ne $statusRaw) { [string]$statusRaw } else { '' }`
    - `$reason = if ($null -ne $reasonRaw) { [string]$reasonRaw } else { '' }`

## Before / After snippets
- Before (REPO PARTIAL synthesis):
```powershell
$repoResult = New-ModeResult ... -OutboxPath (if ($repoEvidence.has_outbox) { $repoEvidence.outbox_dir } else { $null }) -ReportsPath (if ($repoEvidence.has_reports) { $repoEvidence.reports_dir } else { $null })
```
- After:
```powershell
$repoOutboxPath = if ($repoEvidence.has_outbox) { $repoEvidence.outbox_dir } else { $null }
$repoReportsPath = if ($repoEvidence.has_reports) { $repoEvidence.reports_dir } else { $null }
$repoResult = New-ModeResult ... -OutboxPath $repoOutboxPath -ReportsPath $repoReportsPath
```

- Before (Normalize-Result):
```powershell
$status = [string]($statusRaw ?? '')
$reason = [string]($reasonRaw ?? '')
```
- After:
```powershell
$status = if ($null -ne $statusRaw) { [string]$statusRaw } else { '' }
$reason = if ($null -ne $reasonRaw) { [string]$reasonRaw } else { '' }
```

## Validation method
- Verified targeted block update and removal of inline argument-position `if` use in the REPO PARTIAL `New-ModeResult` call.
- Verified `??` removal from the file using search.
- Attempted static parse validation via `pwsh`, but `pwsh` is not installed in this environment.
- Used best-available static checks in this environment: targeted pattern searches and diff inspection only.
- Did not claim full runtime success (no GitHub Actions execution asserted here).

## Risks/blockers
- Compatibility hotfix only; no behavioral redesign was introduced.
- Runtime execution across all environments is not claimed in this report; PowerShell parser validation is blocked locally because PowerShell is unavailable in this environment.
- No blockers encountered.
