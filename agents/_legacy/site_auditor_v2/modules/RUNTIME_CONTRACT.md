# SITE_AUDITOR_V2 Runtime Contract (PS5.1)

- Runtime target: **Windows PowerShell 5.1 compatibility**.
- Runtime-critical constructors must avoid ambiguous overload binding.
- Do **not** use comparer-based generic set constructors.
- Uniqueness handling must use `New-CaseInsensitiveKeyMap`, `Add-KeyIfMissing`, `Test-KeyExists`, and `Get-KeyMapKeys` from `modules/runtime_safe.ps1`.
- `agent.ps1` is orchestrator-only; execution logic belongs in stage modules.
- Failure artifacts must always include `RUN_REPORT.json` and `failure_summary.json` with truthful stage metadata.
