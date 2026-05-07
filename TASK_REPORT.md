# TASK_REPORT

## Summary
- Separated RUN_REPORT `decision_action` from `next_step` in the Site Auditor V3 output helper.
- Kept `decision_action` as the full machine-oriented structured action object for execution and future automation.
- Changed `next_step` into a concise operator-oriented instruction block derived from the selected action instead of duplicating the full action object.
- Preserved the existing RUN_REPORT root fields `decision_action` and `next_step`.
- No protected paths, input modules, route discovery, orchestrator, or validator contracts were modified.

## Changed files
- `agents/site_auditor_v3/lib/decision_next_step.ps1`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v3/run.ps1` (unchanged).
- Output owner remains `agents/site_auditor_v3/modules/07_output.ps1` (still composes RUN_REPORT).
- Helper path remains `agents/site_auditor_v3/lib/decision_next_step.ps1`.

## Risks/blockers
- Dot-sourcing assumes `agents/site_auditor_v3/lib/decision_next_step.ps1` remains present and loadable at runtime.
- Existing validators still require `next_step.action` to match `decision_action.action`; the new `next_step` keeps that compatibility field while no longer copying the full `decision_action` object.
- Branch pushed: `codex/site-auditor-v3-next-step-separation`.
- PR creation URL from GitHub: `https://github.com/ries11217596955-hash/e-factory-agent/pull/new/codex/site-auditor-v3-next-step-separation`.
- PR creation is blocked in this environment because `gh` is unavailable, no GitHub token is present, and the available GitHub connector does not expose pull request creation.

## Validation
- Parser validation:
  - Command: `[System.Management.Automation.Language.Parser]::ParseFile(...)`
  - Evidence: `PARSER_PASS agents/site_auditor_v3/modules/07_output.ps1`
  - Evidence: `PARSER_PASS agents/site_auditor_v3/lib/decision_next_step.ps1`
- `agents/site_auditor_v3/tests/run_and_validate.sh`:
  - Command: `bash agents/site_auditor_v3/tests/run_and_validate.sh`
  - Result: blocked because `bash` is not installed on PATH.
  - Follow-up command: `wsl.exe bash -lc "cd /mnt/c/Users/vmammadov/Documents/e-factory-agent && bash agents/site_auditor_v3/tests/run_and_validate.sh"`
  - Result: blocked because WSL has no installed distro and printed WSL install/help text.
- Equivalent validator steps run directly after a fresh run:
  - Command: `pwsh -NoProfile -File agents/site_auditor_v3/run.ps1 -RequestPath agents/site_auditor_v3/tests/fixtures/smoke.request.json`
  - Evidence: `LATEST_REPORT=C:\Users\vmammadov\Documents\e-factory-agent\agents\site_auditor_v3\runs\20260507_115257\RUN_REPORT.json`
  - Command: `python agents/site_auditor_v3/tests/validate_run_report.py <LATEST_REPORT>`
  - Evidence: `PASS: RUN_REPORT contract`
  - Command: `python agents/site_auditor_v3/tests/guard_v3_build.py <LATEST_REPORT>`
  - Evidence: `V3_BUILD_GUARD_PASS`
  - Command: `RUN_REPORT_PATH=<LATEST_REPORT> python agents/site_auditor_v3/tests/validate_self_build_loop.py`
  - Evidence: `PASS: SELF_BUILD_LOOP_V1`
- Proof that `next_step != decision_action`:
  - Evidence: `decision_action_type: dict`
  - Evidence: `next_step_type: dict`
  - Evidence: `decision_action_keys: ['action', 'action_id', 'next_command_hint', 'priority', 'target_module', 'why']`
  - Evidence: `next_step_keys: ['action', 'instruction', 'target_module', 'why']`
  - Evidence: `next_step_equals_decision_action: False`
  - Evidence: `next_step_instruction: run route_depth_expansion. Owner module: route_audit. Verify evidence before closing.`
