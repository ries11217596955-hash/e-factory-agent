# Codex Operating Contract

## Scope
- Applies to the entire repository tree from this root.

## Execution Mode (PR-First)
1. All non-trivial tasks must follow this order:
   1) commit on the active Codex branch
   2) open or update a pull request
   3) wait for operator review
   4) merge only after explicit approval
2. A UI diff or summary is not considered an applied result.

## Commit and PR Requirements
- Commit is mandatory for non-trivial changes.
- Pull request creation or update is mandatory after commit.
- Auto-merge is forbidden unless explicitly requested by the operator.

## Mandatory Task Report
- `docs/TASK_REPORT.md` is required for every non-trivial task.
- `docs/TASK_REPORT.md` must include these exact sections:
  - Summary
  - Changed files
  - Moved files/folders
  - Current entrypoints/paths
  - Risks/blockers
- PR description must include a short 5-bullet summary.

## Protected Infrastructure Paths
- Do not move, modify, quarantine, or delete active infrastructure paths without explicit permission.
- Protected minimum:
  - `.github/workflows/`

## Safe Cleanup Mode
- For cleanup/refactor tasks, use `_quarantine/` or `_foreign/` first.
- Do not delete directly unless explicitly requested.
- Record cleanup actions in `docs/TASK_REPORT.md`.

## Change Scope Policy
- Prefer explicit file-level changes.
- Do not perform broad refactors unless explicitly requested.
- If uncertain, state uncertainty instead of guessing.
