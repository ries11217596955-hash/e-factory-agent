## Summary
- Implemented PACK 4 for `SITE_AUDITOR_V2` to synthesize one deterministic `system_problem` from HIGH-confidence findings and drive the full decision/action chain from that object.
- Added universal surface normalization (`entry_surface`, `explanation_surface`, `decision_surface`, `action_surface`, `terminal_surface`, `unknown_surface`) and attached `surface_type` to findings and page verdicts.
- Added compact `interaction_explanation` into `system_problem` with observable chain fields: entry surface, expected outcome, actual outcome, failure point, and why it matters.
- Rebuilt RU/EN human reports to compressed structure: single main system problem, max 3 evidence items, max 3 action bullets, optional single limitation block, compact technical snapshot.
- Added stronger consistency lock checks for strongest action synchronization across `system_problem`, `decision_summary`, `next_strongest_move`, `ACTION_SUMMARY`, and human reports.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - **Surface normalization block**: added `Get-SurfaceTypeByPageType` and propagated `surface_type` into findings/page verdicts.
  - **System problem synthesis block**: replaced micro-cluster-only logic with deterministic `system_problem` synthesis rules:
    - repeated HIGH finding type across >=2 surfaces => one system problem,
    - otherwise fallback to strongest single defect,
    - limitation-only => LIMITATION,
    - no defects => CLEAN.
  - **Decision override block**: decision summary now derives primary issue/action from `system_problem` title/strongest action.
  - **Interaction explanation block**: added compact universal behavior explanation inside `system_problem.interaction_explanation`.
  - **Human report rendering block**: replaced long-form sections with compressed order and limits.
  - **Consistency lock block**: added action-chain strict equality checks and max-item guardrails for actions/evidence.
  - **Fallback report block**: updated fallback payload fields to match new compact report schema.
- `docs/TASK_REPORT.md`
  - Replaced with PACK 4 implementation report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Route discovery core unchanged.
- Screenshot engine core unchanged.
- Memory files unchanged.
- ZIP/REPO modes unchanged.

## Risks/blockers
- PowerShell runtime is not available in this environment (`pwsh` missing), so live execution validation could not be performed.
- RU/EN report bodies are compressed and structurally aligned, but style tuning may still need minor copy edits after runtime samples.
- Stronger consistency lock can now fail generation on wording/field mismatches that previously passed; this is intentional but stricter operationally.
- No protected/forbidden paths were modified.

## Universal surface normalization rules
- `HOME` -> `entry_surface`
- `ARTICLE` -> `explanation_surface`
- `DECISION` -> `decision_surface`
- `TOOL` -> `action_surface`
- `HUB` -> `terminal_surface`
- any unknown type -> `unknown_surface`
- Existing route/page fields are preserved for compatibility; `surface_type` is additive.

## System problem synthesis rules
- Input set: HIGH-confidence findings only.
- If same finding type repeats across >=2 normalized surfaces: synthesize one DEFECT system problem.
- If no multi-surface repeat but at least one defect: fallback to strongest single defect as system problem.
- If no defects but limitations exist: system problem category LIMITATION.
- If no defects and no limitations: system problem category CLEAN.
- System problem output fields:
  - `problem_type`
  - `category`
  - `title`
  - `description`
  - `affected_surfaces_count`
  - `representative_examples` (max 3)
  - `strongest_action`
  - `confidence`
  - `interaction_explanation`

## Report compression rules
- One main system problem only.
- Supporting evidence max 3 lines.
- Actions max 3 bullets (main action first).
- Limitation section max 1 line and rendered only when needed.
- No duplicate explanation sections.
- Human report omits weak/noisy intermediate artifacts and raw route dumps.

## Rollback instructions by file/block
1. `agents/site_auditor_v2/agent.ps1`:
   - Remove `Get-SurfaceTypeByPageType` and all `surface_type` assignments in findings/page verdicts.
   - Restore pre-PACK4 micro-cluster/system-problem block (cluster summary + previous override logic).
   - Restore previous human report payload schema (`checked_lines`, `main_finding`) and previous `New-ClientReportHtml` layout.
   - Remove newly added consistency checks for strongest-action chain and report compression limits.
2. `docs/TASK_REPORT.md`:
   - Restore previous task report content from git history.
