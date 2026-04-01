# SITE_AUDITOR_AGENT

Status: active packaged unit
Source of truth for this repo: `agents/site_auditor_agent/`
Entrypoint: `run.ps1`

Purpose:
- repo fetch through GitHub API ZIP
- inventory and semantic audit
- links / render / screenshot audit
- packaged report delivery

Verified package facts:
- `AGENT_PASSPORT.txt` present
- `run.ps1` and `agent.ps1` present
- module scripts extracted into this folder
- output contract documented as `audit_result.json`, `HOW_TO_FIX.json`, priority reports, `REPORT.txt`, `DONE.ok/DONE.fail`

Boundary:
- package presence does not equal verified runtime PASS
- release ZIPs should not be treated as source of truth once files are materialized here
