## Summary
Hardened LINK mode output guarantees by locking RUN_REPORT contract fields, enforcing deterministic artifact declarations, and adding workflow regression checks for contract/artifact drift and pass/fail consistency.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `.github/workflows/site-auditor-v2-link.yml`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Agent entrypoint: `agents/site_auditor_v2/agent.ps1`
- Workflow entrypoint: `.github/workflows/site-auditor-v2-link.yml`
- Deterministic top-level outputs kept for operator access: `RUN_REPORT.json`, `ACTION_REPORT.txt` (and other core outputs when produced)
- Workflow upload source: `site_auditor_v2_artifact_bundle/` containing exactly `RUN_REPORT.produced_artifacts`

## Risks/blockers
- Workflow assumes `jq` is available on `ubuntu-latest` runner (standard GitHub-hosted image expectation).
