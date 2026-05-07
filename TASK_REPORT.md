# TASK_REPORT

## Summary
- Normalized Site Auditor V3 build action ownership so `09_capability_builder` emits `build_recommendation` instead of acting like a decision layer.
- Preserved `next_action` in `09_capability_builder` as a backward-compatible alias of `build_recommendation`.
- Updated `10_post_build_decision` to prefer `build.build_recommendation` over `build.next_action` before converting build state into `decision_action`.
- Added validator checks that build output does not emit `decision_action` and that any compatibility `next_action` mirrors `build_recommendation`.
- No forbidden modules, lib files, orchestrator, runtime execution module, generated runs, or deliverables were modified.

## Changed files
- `agents/site_auditor_v3/modules/09_capability_builder.ps1`
- `agents/site_auditor_v3/modules/10_post_build_decision.ps1`
- `agents/site_auditor_v3/tests/validate_run_report.py`
- `agents/site_auditor_v3/tests/guard_v3_build.py`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v3/run.ps1` (unchanged).
- Execution owner remains `agents/site_auditor_v3/modules/08_execution.ps1` (unchanged).
- Base decision owner remains `agents/site_auditor_v3/modules/06_decision.ps1` (unchanged).
- Build recommendation owner is `agents/site_auditor_v3/modules/09_capability_builder.ps1`.
- Build-to-decision promotion owner is `agents/site_auditor_v3/modules/10_post_build_decision.ps1`.

## Risks/blockers
- `next_action` is still emitted as a compatibility alias for existing downstream readers.
- Bash wrapper validation may be blocked on this Windows environment if no usable Bash shell is available.

## Validation
- Parser validation:
  - Command: `[System.Management.Automation.Language.Parser]::ParseFile(...)`
  - Evidence: `PARSER_PASS agents/site_auditor_v3/modules/09_capability_builder.ps1`
  - Evidence: `PARSER_PASS agents/site_auditor_v3/modules/10_post_build_decision.ps1`
- Python validator syntax:
  - Command: `python -m py_compile agents/site_auditor_v3/tests/validate_run_report.py agents/site_auditor_v3/tests/guard_v3_build.py`
  - Evidence: command exited `0`.
- `agents/site_auditor_v3/tests/run_and_validate.sh`:
  - Command: `bash agents/site_auditor_v3/tests/run_and_validate.sh`
  - Result: blocked because `bash` is not installed on PATH in this Windows environment.
- Equivalent direct run:
  - Command: `pwsh -NoProfile -File agents/site_auditor_v3/run.ps1 -RequestPath agents/site_auditor_v3/tests/fixtures/smoke.request.json`
  - Evidence: `LATEST_REPORT=C:\Users\vmammadov\Documents\e-factory-agent\agents\site_auditor_v3\runs\20260507_123933\RUN_REPORT.json`
  - Command: `python agents/site_auditor_v3/tests/validate_run_report.py <LATEST_REPORT>`
  - Evidence: `PASS: RUN_REPORT contract`
  - Command: `python agents/site_auditor_v3/tests/guard_v3_build.py <LATEST_REPORT>`
  - Evidence: `V3_BUILD_GUARD_PASS`
  - Command: `RUN_REPORT_PATH=<LATEST_REPORT> python agents/site_auditor_v3/tests/validate_self_build_loop.py`
  - Evidence: `PASS: SELF_BUILD_LOOP_V1`
- Proof that `build_recommendation` exists when build emits an action:
  - Evidence: `build_status: ALREADY_AVAILABLE`
  - Evidence: `build_has_build_recommendation: True`
  - Evidence: `build_has_next_action_alias: True`
  - Evidence: `next_action_alias_matches: True`
  - Evidence: `build_has_decision_action: False`
- Proof that `post_build_decision.decision_action` is derived by 10, not emitted directly by 09:
  - Command: direct `Invoke-Module10PostBuildDecision` with distinct `build_recommendation` and `next_action` values.
  - Evidence: `POST10_STATUS=OK`
  - Evidence: `POST10_SOURCE=post_build_decision`
  - Evidence: `POST10_REASON=build generated recommendation`
  - Evidence: `POST10_DECISION_ACTION_ID=integrate_generated_capability`
  - Evidence: `POST10_USED_BUILD_RECOMMENDATION=True`
  - Evidence: `POST10_IGNORED_NEXT_ACTION_ALIAS=True`
  - Evidence: `GREP_PASS 09 emits no decision_action`
- Grep proof:
  - Evidence: `agents/site_auditor_v3/modules/09_capability_builder.ps1:61:                build_recommendation = $buildRecommendation`
  - Evidence: `agents/site_auditor_v3/modules/09_capability_builder.ps1:138:            build_recommendation = $buildRecommendation`
  - Evidence: `agents/site_auditor_v3/modules/10_post_build_decision.ps1:9:    $buildRecommendation = if ($build -and $build.build_recommendation) {`
  - Evidence: `agents/site_auditor_v3/modules/10_post_build_decision.ps1:10:        $build.build_recommendation`
  - Evidence: `agents/site_auditor_v3/modules/08_execution.ps1:7:    $action = $PipelineState.decision.decision_action`
