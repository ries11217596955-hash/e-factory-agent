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
---

## Active AGENTOPS line

Current AGENTOPS build/test focus:
- `agents/site_auditor_v3/`
- current development contour = session-ledger / long-run audit orchestration

Retained older runtime line:
- `agents/site_auditor_v2/`
- retained in-repo, but not the current AGENTOPS build/test focus

Architecture rule:
- `run.ps1` / orchestrator = execution coordinator only
- owner logic must stay in modules/ or lib/

Repair flow:
run → inspect → isolate → patch → test → commit

Forbidden:
- blind CI edits
- broad refactor
- legacy paths as active
---

## Operator / tool role matrix

### ChatGPT / operator assistant
Use for:
- artifact interpretation
- bottleneck choice
- decision and next action selection
- writing Codex tasks when Codex is actually needed

Do not use as a truth source without artifacts.

### Codex
Use only when:
- root cause is known
- target file/function/contract is known
- acceptance criteria are explicit
- the patch is better delegated than directly applied through the terminal

Do not use Codex for broad investigation, vague debugging, or deterministic micro-patches that are safer to apply directly.

### CodeSpace / terminal execution lane
Use for:
- runtime verification
- wrapper execution
- diagnostics
- local diff/status checks
- artifact generation and evidence confirmation

Terminal output is runtime evidence; it is not a substitute for RUN_REPORT/runpack truth.

### Agent
Use when:
- execution is required
- evidence/report/runpack must be produced

Agent must produce a usable result or a diagnostic artifact.
Silent failure is product failure.

---

## Runtime truth discipline

For AGENTOPS work, the first runtime truth file is:

1. RUN_REPORT.json
2. SELF_DIAGNOSTIC.json
3. ACTION_SUMMARY.json
4. AGENT_MAP.json / AGENT_MAP.md
5. visual_manifest.json

RUN_REPORT must remind the operator:
- role: System Operator / Product Lead
- goal: Traffic -> Decision -> Action -> Monetization
- rule: artifact truth over memory
- workflow: run -> inspect -> isolate -> patch -> test -> commit
- architecture: orchestrator coordinates; module-owned logic stays under modules/ or lib/

If RUN_REPORT contradicts physical artifacts, artifact consistency is the next bottleneck.
Do not patch business logic until report truth is aligned.

---

## Execution contour reference

For the current Windows operator contour, use:
- `agents/site_auditor_v3/docs/EXECUTION_CONTOUR.md`

This file defines:
- PowerShell role
- Git Bash wrapper role
- Python analysis role
- Node / capture role
- the local guard against invoking the wrong `bash` implementation
