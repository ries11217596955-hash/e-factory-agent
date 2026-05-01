# site_auditor_v2 (LINK-first MVP scaffold)

This directory is the clean production root for Sprint A of `site_auditor_v2`.

## Active mode

- `MODE=LINK` is the only active mode.
- Any other mode returns an honest failure (`exit 1`) and writes both `RUN_REPORT.json` and `failure_summary.json`.

## Dry local invocation

```powershell
pwsh -File ./agents/site_auditor_v2/agent.ps1 -Mode LINK -BaseUrl "https://example.com"
```

## Deterministic output files

Given `MODE` + `BASE_URL`, output is written under:

- `agents/site_auditor_v2/output/<mode>_<hash>/RUN_REPORT.json`
- `agents/site_auditor_v2/output/<mode>_<hash>/failure_summary.json` (only on fail)

`<hash>` is a stable SHA-256 prefix derived from `MODE|BASE_URL`.
