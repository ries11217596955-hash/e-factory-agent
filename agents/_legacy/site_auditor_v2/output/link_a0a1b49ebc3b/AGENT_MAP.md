# SITE_AUDITOR_V2 — AGENT MAP

## AGENT IDENTITY
SITE_AUDITOR_V2 is a LINK-mode audit orchestrator that produces bounded evidence and operator handoff artifacts.

## ACTIVE PRODUCT SCOPE
Universal Audit Engine. Current LINK run is one execution mode, not the whole product.

## CURRENT EXECUTION MODE + LAYER
Execution mode: LINK
Current layer: REPORT_LAYER (bounded to observable LINK artifacts only).

## ORCHESTRATOR RULE
agent.ps1 is orchestrator. New behavior must be module/contract, not giant runtime growth.

## STAGES
ENTRY -> LINK_FETCH -> ROUTE_EXTRACTION -> ROUTE_SELECTION -> CAPTURE -> RECON -> REPORT_LAYER -> OUTPUT -> HUMAN_REPORT

## SYSTEM MAP (MINIMAL)
- route layer -> builds routes
- capture layer -> screenshots
- recon -> evaluation
- report -> decisions
- output -> artifacts
- file pointers: agent.ps1, modules/stage_link_fetch.ps1, modules/stage_capture_reconciliation.ps1, modules/report_layer.ps1, lib/post_output.ps1

## LAYER CONTRACT MAP
### ROUTE_LAYER
- owner file: modules/stage_link_fetch.ps1
- purpose: discover LINK-visible routes and produce normalized route candidates for selection.
- inputs: site_url, execution mode, route budget controls, LINK fetch responses.
- outputs: selected routes, route metadata, ROUTES_SUMMARY.json route truth.
- failure signals: LINK_FETCH_* errors, ROUTE_VALIDATION_* errors, route contract mismatches attributed to modules/stage_link_fetch.ps1.
### CAPTURE_LAYER
- owner file: tools/capture_visuals.mjs
- purpose: capture deterministic screenshots for each selected route.
- inputs: selected route list, viewport/device options, capture timeout/budget.
- outputs: screenshot files, capture statuses, visual_manifest.json entries.
- failure signals: CAPTURE_* stage errors, missing screenshot artifacts, visual manifest gaps attributed to tools/capture_visuals.mjs.
### RECON_LAYER
- owner file: modules/stage_capture_reconciliation.ps1
- purpose: reconcile route selection with capture evidence before reporting.
- inputs: selected routes, capture results, visual manifest, route budget overflow detail.
- outputs: reconciled route verdict inputs, evidence completeness flags, limitation signals.
- failure signals: RECON_* / RECONCILIATION_* errors, evidence mismatch failures attributed to modules/stage_capture_reconciliation.ps1.
### REPORT_LAYER
- owner file: modules/report_layer.ps1
- purpose: synthesize findings and enforce RUN_REPORT contract consistency.
- inputs: reconciled route evidence, audit summaries, decision/action payloads.
- outputs: RUN_REPORT decision payload, operator_memory_bridge guidance, ACTION_SUMMARY alignment.
- failure signals: CONSISTENCY_LOCK_FAILED, RUN_REPORT_BUILD_FAILED, report contract violations attributed to modules/report_layer.ps1.
### OUTPUT_LAYER
- owner file: lib/post_output.ps1
- purpose: produce operator-facing report text and stable handoff artifacts.
- inputs: RUN_REPORT.json, operator_memory_bridge.self_explanation, summary artifacts.
- outputs: REPORT_EN.txt, REPORT_RU.txt, AGENT_FAILURE_REPORT/AGENT_OPERATOR_HANDOFF on fail.
- failure signals: HUMAN_REPORT_* and POST_OUTPUT_* write/read errors attributed to lib/post_output.ps1.

## MODULE / FILE RESPONSIBILITY MAP
- agent.ps1 = orchestrator and stage control
- modules/stage_link_fetch.ps1 = LINK fetch and route discovery
- modules/stage_route_keys.ps1 = route normalization keys
- modules/stage_capture_reconciliation.ps1 = evidence reconciliation gate
- modules/report_layer.ps1 = findings synthesis + operator memory contract
- lib/post_output.ps1 = REPORT_EN/RU operator text output
- contracts/run_report.schema.json = RUN_REPORT contract

## OUTPUT CONTRACT
- RUN_REPORT.json = read first
- failure_summary.json = read only if FAIL
- ROUTES_SUMMARY.json = route truth
- AUDIT_SUMMARY.json = audit counts
- visual_manifest.json = visual evidence
- REPORT_EN.txt / REPORT_RU.txt = human reports
- AGENT_MAP.md = map of modules, outputs, and artifact routing

## ARTIFACT ROUTING
Only files inside agents/site_auditor_v2/output/<run-id>/ are guaranteed to appear in uploaded artifact.

## REPAIR RULE
Fix one layer only. Do not switch to WEBOPS. Do not patch multiple layers. Do not expand features before stabilizing the current defect.


## RUNTIME SNAPSHOT
- RUN_REPORT.json: root=yes; output=yes
- ROUTES_SUMMARY.json: root=yes; output=yes
- AUDIT_SUMMARY.json: root=yes; output=yes
- ACTION_SUMMARY.json: root=yes; output=yes
- visual_manifest.json: root=yes; output=yes
- failure_summary.json: root=no; output=no
- REPORT_EN.txt: root=yes; output=no
- REPORT_RU.txt: root=yes; output=no
## CURRENT BASELINE
GREEN LINK CI baseline exists. Preserve it.
