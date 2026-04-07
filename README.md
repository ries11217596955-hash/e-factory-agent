# E-Factory Agent Repo

Purpose:
- keep canonical source layout for active agents
- separate canonical source files from quarantined legacy material
- keep the repository root non-mixed and predictable

Current active agents:
- `GH_BATCH`
- `SITE_AUDITOR_AGENT`

Canonical root layout:
- `agents/` = source-of-truth agent code and related assets
- `scripts/` = operational scripts used by canonical workflows
- `config/` = active configuration
- `docs/` = documentation, closeout notes, and migration records
- `tests/` = automated checks and validation assets
- `_quarantine/` = retained legacy/non-canonical material (not deleted)
- `_foreign/` = retained non-canonical web/content trees
- `.gitignore`
- `README.md`

Rules for this repo:
1. Active agent source must live under `agents/`.
2. Runtime/output and queue-era folders must not remain at root.
3. Legacy web/content trees must not remain at root.
4. Legacy artifacts are preserved by moving them into `_quarantine/` or `_foreign/`.
5. Entrypoints for active agents must remain valid after cleanup.
