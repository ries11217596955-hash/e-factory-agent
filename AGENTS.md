# AGENTS.md

## Purpose
This repository is operated under a controlled Codex execution model.
All changes must be safe, minimal, and reviewable.

---

## Execution model (PR-FIRST)

All work is considered applied only after:

Task → branch commit → PR → operator review → merge

Rules:
- Never treat UI diff as applied result
- Never skip PR
- Never merge automatically unless explicitly allowed by safe rules

---

## Task discipline

All tasks must be executed using structured format:
- Task
- Repository scope (Allowed / Forbidden)
- Mode
- Requirements
- Reporting

Free-form or vague tasks must not be executed as-is.

---

## Scope control

Every task must define:

Allowed paths:
- Explicit list of files or directories

Forbidden paths (minimum):
- .github/workflows/
- config files
- entrypoints
- runtime logic
- deployment configuration

Codex must NOT expand scope beyond what is defined.

---

## Commit convention

Use structured commits:

type(scope): short description

Examples:
- fix(tools): add missing content blocks
- feat(agent): improve audit detection
- chore(config): add codex config

---

## Branch naming

Use:

codex/<area>-<task>

Examples:
- codex/tools-fix
- codex/start-here-content
- codex/agent-audit-fix

---

## Reporting (MANDATORY)

Each non-trivial task must produce:

docs/TASK_REPORT.md

With sections:
- Summary
- Changed files
- Moved files/folders
- Current entrypoints/paths
- Risks/blockers

Also include 5-bullet summary in PR description.

---

## Repo safety rules

Protected paths (NEVER change without explicit instruction):

- .github/workflows/
- deployment config
- routing/entrypoints
- runtime logic
- agent execution flow
- packaging/install logic

If task requires touching these → STOP and ask.

---

## Cleanup / refactor (SAFE MODE)

If cleanup is requested:

1. Move files first:
   - _quarantine/
   - _foreign/

2. Do NOT delete immediately

3. Document all actions in TASK_REPORT.md

4. Do NOT break:
   - workflows
   - entrypoints
   - runtime
   - repo structure

---

## Safe auto-merge rules

Auto-merge is allowed ONLY if ALL conditions are met:

- 1–2 files changed
- changes are inside allowed scope
- no protected paths touched
- no structural changes
- TASK_REPORT.md present
- changes are small and deterministic

Otherwise:
→ require operator review

---

## Default behavior

- Minimal changes only
- No broad refactor
- No speculative improvements
- No hidden changes
- No scope expansion

If uncertain:
→ state uncertainty, do not guess

---

## Deliverable expectation

Every task must end with:

- commit created
- PR opened
- TASK_REPORT.md created/updated
- PR summary present
- no auto-merge unless safe conditions are met
