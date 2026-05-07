# TASK_REPORT

## Summary
- Normalized Site Auditor V3 build truth gate coverage in `10_post_build_decision`.
- `build_truth_gate` is now emitted for `GENERATED`, `ALREADY_AVAILABLE`, `SKIPPED`, and `FAILED` build statuses.
- Preserved generated build truth checks and decision action precedence.
- Added validator coverage requiring a checked `build_truth_gate` with a non-empty reason whenever build status exists.
- No forbidden modules, builder output shape, execution logic, output writer, lib files, generated runs, or deliverables were modified.

## Changed files
- `agents/site_auditor_v3/modules/10_post_build_decision.ps1`
- `agents/site_auditor_v3/tests/validate_run_report.py`
- `agents/site_auditor_v3/tests/guard_v3_build.py`
- `TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v3/run.ps1` (unchanged).
- Output owner remains `agents/site_auditor_v3/modules/07_output.ps1` (unchanged).
- Build owner remains `agents/site_auditor_v3/modules/09_capability_builder.ps1` (unchanged).
- Build truth gate owner is `agents/site_auditor_v3/modules/10_post_build_decision.ps1`.

## Risks/blockers
- Bash wrapper validation may be blocked on this Windows environment if no usable Bash shell is available.
- `ALREADY_AVAILABLE` passes only when the target file exists, mode is `EXISTING_HANDLER`, and the existing function is either command-available or physically present in the target file.

## Validation
- Parser validation:
  - Command: `[System.Management.Automation.Language.Parser]::ParseFile(...)`
  - Evidence: `PARSER_PASS agents/site_auditor_v3/modules/10_post_build_decision.ps1`
- Python validator syntax:
  - Command: `python -m py_compile agents/site_auditor_v3/tests/validate_run_report.py agents/site_auditor_v3/tests/guard_v3_build.py`
  - Evidence: command exited `0`.
- `agents/site_auditor_v3/tests/run_and_validate.sh`:
  - Command: `bash agents/site_auditor_v3/tests/run_and_validate.sh`
  - Result: blocked because `bash` is not installed on PATH in this Windows environment.
- Equivalent direct smoke run:
  - Command: `pwsh -NoProfile -File agents/site_auditor_v3/run.ps1 -RequestPath agents/site_auditor_v3/tests/fixtures/smoke.request.json`
  - Evidence: `LATEST_REPORT=C:\Users\vmammadov\Documents\e-factory-agent\agents\site_auditor_v3\runs\20260507_125642\RUN_REPORT.json`
  - Command: `python agents/site_auditor_v3/tests/validate_run_report.py <LATEST_REPORT>`
  - Evidence: `PASS: RUN_REPORT contract`
  - Command: `python agents/site_auditor_v3/tests/guard_v3_build.py <LATEST_REPORT>`
  - Evidence: `V3_BUILD_GUARD_PASS`
  - Command: `RUN_REPORT_PATH=<LATEST_REPORT> python agents/site_auditor_v3/tests/validate_self_build_loop.py`
  - Evidence: `PASS: SELF_BUILD_LOOP_V1`
- Proof for normal smoke run:
  - Evidence: `build_status: ALREADY_AVAILABLE`
  - Evidence: `build_truth_gate_present: True`
  - Evidence: `build_truth_gate.checked: True`
  - Evidence: `build_truth_gate.passed: True`
  - Evidence: `build_truth_gate.reason: existing handler verified`
  - Evidence: `build_truth_gate.mode: EXISTING_HANDLER`
  - Evidence: `build_truth_gate.existing_function: Invoke-RouteDiscoveryInternal`
  - Evidence: `build_truth_gate.command_available: False`
  - Evidence: `build_truth_gate.function_in_target: True`
- Direct status checks:
  - Evidence: `SKIPPED_GATE_CHECKED=True`
  - Evidence: `SKIPPED_GATE_PASSED=True`
  - Evidence: `SKIPPED_GATE_REASON=no build task`
  - Evidence: `FAILED_GATE_CHECKED=True`
  - Evidence: `FAILED_GATE_PASSED=False`
  - Evidence: `FAILED_GATE_REASON=unsupported capability`
