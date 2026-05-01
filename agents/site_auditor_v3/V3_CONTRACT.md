# SITE_AUDITOR_V3 CONTRACT

## Purpose
Universal audit engine.
Current mode: LINK.
Website audit is one execution lane, not total product scope.

## Core loop
Input -> Audit -> Evidence -> Truth -> Decision -> Action -> Output

## Architecture rule
run.ps1 is orchestrator only.
No business logic in run.ps1.
No report text hardcoded in run.ps1.
No fake static AGENT_MAP.

## Required output
- RUN_REPORT.json
- ACTION_SUMMARY.json
- AGENT_MAP.json
- visual_manifest.json
- visual_capture_input.json
- screenshots/ when capture enabled
- SELF_DIAGNOSTIC.json only when FAIL or PARTIAL

## Forbidden output
- REPORT_EN.txt
- REPORT_RU.txt
- ACTION_REPORT.txt
- TEST_HUMAN_REPORT.txt
- root-level runtime reports
- duplicate human reports
- linked artifacts that do not physically exist

## Module ownership
01_input.ps1
- owns input normalization
- output: input_result.json object

02_route_audit.ps1
- owns route discovery and route status
- output: route_audit_result.json object

03_selection.ps1
- owns route selection for capture
- output: selection_result.json object

04_capture.ps1
- owns visual_capture_input.json and visual_manifest.json
- uses tools/capture_visuals.mjs
- output: capture_result.json object

05_reconcile.ps1
- owns evidence verification
- output: reconciliation_result.json object

06_decision.ps1
- owns findings, priority, action
- output: action_summary object

07_output.ps1
- owns final RUN_REPORT.json and AGENT_MAP.json
- writes final runpack once

## AGENT_MAP rule
AGENT_MAP must be generated from module registry.
No manually written map text.

## Truth rule
RUN_REPORT is assembled once at the end.
No later rewrite except atomic final write.

## Module law

MODULE = FUNCTION ONLY.

Allowed inside module:
- function definition
- parameter validation
- return object

Forbidden inside module:
- auto-run code
- Write-Host
- file writes
- root/output writes
- duplicated function blocks
- commits
- git commands
- hidden fallback output

Only run.ps1 may call modules.
Only output module may write final runpack files.
