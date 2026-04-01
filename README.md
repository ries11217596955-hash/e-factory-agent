# E-Factory Agent Repo

Purpose:
- keep canonical source layout for active agents
- separate source files from release packages
- reduce root-level archive clutter and source ambiguity

Current active agents:
- `GH_BATCH`
- `SITE_AUDITOR_AGENT`

Canonical layout:
- `agents/gh_batch/` = source-of-truth files for GH_BATCH
- `agents/site_auditor_agent/` = source-of-truth files for SITE_AUDITOR_AGENT
- `releases/` = release-package storage only
- `docs/` = repo-level structure, cleanup and packaging guidance

Rules for this repo:
1. Root must not be used as long-term storage for versioned ZIP releases.
2. Active agent source must live under `agents/`.
3. Release ZIP is a deliverable, not the source of truth.
4. Runtime outputs, inbox/outbox state and logs must stay outside source folders unless explicitly documented.
5. Packaging presence must not be written as runtime PASS.

This cleanup patch establishes canonical folders for the two active agents. Old root ZIP files should be removed or moved after this patch is applied.
