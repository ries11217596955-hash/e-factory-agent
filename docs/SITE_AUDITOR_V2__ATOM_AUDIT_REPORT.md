# SITE_AUDITOR_V2 ATOM AUDIT REPORT

## 1. EXECUTIVE SUMMARY
- Scope audited: active LINK execution path with full static inspection of target subtree.
- Audit confirms nine evidence-backed defects across active path, contracts, and workflow integration.
- Primary active-path blocker: route extraction rejects non-root relative href values (e.g., `about`, `./x`), causing route under-discovery and possible ROUTE_EXTRACTION fail conditions.
- Strongest repair batch: **BATCH-A** (route extraction + surface-context contract drift) because it directly stabilizes active LINK execution correctness before schema/workflow alignment.
- No runtime behavior was asserted without code evidence. Any runtime-only uncertainty is marked as unresolved.

## 2. REPO INVENTORY

### Target subtree inventory by role

#### Orchestrator
- `agents/site_auditor_v2/agent.ps1`

#### Stage modules
- `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
- `agents/site_auditor_v2/modules/stage_route_keys.ps1`
- `agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1`

#### Utility/support modules
- `agents/site_auditor_v2/modules/runtime_safe.ps1`
- `agents/site_auditor_v2/modules/util_io.ps1`
- `agents/site_auditor_v2/modules/util_json.ps1`
- `agents/site_auditor_v2/modules/report_safe_helpers.ps1`
- `agents/site_auditor_v2/modules/report_layer.ps1`
- `agents/site_auditor_v2/modules/surface_context.ps1`
- `agents/site_auditor_v2/modules/self_build_protocol.ps1`

#### Utility (Node capture)
- `agents/site_auditor_v2/tools/capture_visuals.mjs`

#### Contracts / schema
- `agents/site_auditor_v2/contracts/run_report.schema.json`
- `agents/site_auditor_v2/contracts/failure_summary.schema.json`

#### Workflow
- `.github/workflows/site-auditor-v2-link.yml`

#### Test
- `tests/check_route_contract.ps1`

#### Docs/support in subtree
- `agents/site_auditor_v2/modules/RUNTIME_CONTRACT.md`

## 3. CURRENT LINK EXECUTION PATH

### Entry-to-end walk (active LINK flow)
1. **Entrypoint and mode gating**
   - Source: `agent.ps1`
   - Input shape: scalar params `Mode`, `BaseUrl`
   - Output/transition: normalized mode + canonical base URL + initialized report object
   - Markers: `STAGE: ENTRY`
   - Unguarded zone: none high-risk here.

2. **Module import + runtime helper availability**
   - Source: `agent.ps1` dot-sourcing `modules/*.ps1`
   - Input: file availability
   - Output: function namespace loaded
   - Markers: none explicit
   - Unguarded zone: import failure precedes rich stage markers.

3. **LINK_FETCH stage**
   - Source: `agent.ps1` → `Get-LinkSignals` in `stage_link_fetch.ps1`
   - Input shape: scalar URL
   - Output shape: ordered object (`status_code`, `title`, `html_length`, etc.)
   - Markers: `STAGE: LINK_FETCH`
   - Unguarded zone: network errors inside `Invoke-WebRequest` bubble to global catch.

4. **ROUTE_EXTRACTION stage**
   - Source: `agent.ps1` → `Get-ShallowRoutes`
   - Input shape: scalar root URL, max int
   - Output shape: ordered object with arrays (`routes`, reasons, samples)
   - Markers: `STAGE: ROUTE_EXTRACTION`, plus `ROUTE_EXTRACTION:*` markers
   - Unguarded zone: href-filter logic is custom inline and rejects many relative links.

5. **Post-route summaries**
   - Source: `agent.ps1`
   - Output artifacts: `ROUTES_SUMMARY.json`, `ACTION_SUMMARY.json`, `AUDIT_SUMMARY.json`, `ACTION_REPORT.txt`
   - Markers: `POST_ROUTE:ROUTES_SUMMARY_WRITTEN`, `POST_ROUTE:AUDIT_SUMMARY_WRITTEN`, `POST_ROUTE:ACTION_REPORT_WRITTEN`
   - Unguarded zone: none critical.

6. **ROUTE_SELECTION stage**
   - Source: `agent.ps1` → `Get-VisualTargets` in `stage_route_keys.ps1`
   - Input shape: summary object with `routes[]`
   - Output shape: `{ selected_routes[], overflow_routes[], selection_strategy }`
   - Markers: `STAGE: ROUTE_SELECTION` + detailed route-selection markers
   - Unguarded zone: duplicate helper logic in module increases drift risk.

7. **Visual target capture invocation (CAPTURE)**
   - Source: `agent.ps1` → `Invoke-VisualCapture` → `capture_visuals.mjs`
   - Input shape: pages array in JSON (`visual_capture_input.json`)
   - Output shape: `visual_manifest.json`, `screenshots/*.png`
   - Markers: **No `Write-BootstrapStageTrace` marker for CAPTURE before tool call**
   - Unguarded zone: external node call corridor has weak stage-localized trace.

8. **Manifest handling + route normalization pass**
   - Source: `agent.ps1`
   - Input shape: manifest object `pages[]`
   - Output shape: normalized `pages[].route`, `pages[].source_url`
   - Markers: none explicit beyond stage context
   - Unguarded zone: if manifest shape drifts, failures occur before explicit sub-markers.

9. **RECONCILIATION prep and reconciliation**
   - Source: `agent.ps1` → `Invoke-CaptureReconciliationPrepStage` and `Invoke-EvidenceReconciliation`
   - Input: selected routes, manifest pages, capture counters
   - Output: reconciliation summary object + `report.capture_report` + `report.evidence_reconciliation`
   - Markers: `RECON: PREP_OK`, `RECON: EVIDENCE_OK`, status markers
   - Unguarded zone: none major after prep marker.

10. **SURFACE_CONTEXT and REPORT_LAYER**
    - Source: `agent.ps1` + `surface_context.ps1` + `report_layer.ps1`
    - Input: routes signals + manifest signals + findings lists
    - Output: decision objects, human payloads, action summary
    - Markers: phase tracking via `$failurePhase`, no explicit `STAGE:` marker write
    - Unguarded zone: signal-map field drift affects context logic silently.

11. **Final artifact write expectations**
    - Success path writes `RUN_REPORT.json` and deterministic copies.
    - Failure path writes `failure_summary.json`, `AGENT_FAILURE_REPORT.txt`, `AGENT_OPERATOR_HANDOFF.json`, then `RUN_REPORT.json`.
    - Workflow later uploads artifacts listed in `RUN_REPORT.produced_artifacts`.

## 4. ACTIVE-PATH BLOCKERS
1. **SAV2-D001 (P0)** Route extraction rejects non-root relative hrefs.
2. **SAV2-D002 (P1)** SURFACE_CONTEXT reads `first_screen_text_length` missing in producer map.
3. **SAV2-D004/D005/D006 (P1)** Contract-first schema drift (run_report + failure_summary) makes declared contracts stale against actual active outputs.
4. **SAV2-D008 (P1)** Active workflow executes on Ubuntu pwsh (PS7), not PS5.1 runtime target.

## 5. DEFECT CLASSES
- `active_path_route_extraction`
- `return_contract_mismatch`
- `trace_localization_gap`
- `schema_contract_drift`
- `runtime_contract_gap`
- `module_internal_drift`
- `orchestrator_module_boundary`

## 6. REPEATED PATTERNS
- **Schema drift pattern**: D004, D005, D006 all show contract JSON mismatch with currently emitted report/failure payloads.
- **Duplicate logic/drift pattern**: D007 and D009 both show duplicated logic corridors that increase divergence risk.
- **Trace gap pattern**: D003 indicates marker inconsistency at a critical stage boundary.

## 7. ORCHESTRATOR VS MODULE BOUNDARY ASSESSMENT
- `agent.ps1` remains orchestrator-plus-heavy-business-logic instead of orchestration-only, especially in SURFACE_CONTEXT and REPORT_LAYER assembly.
- Current module split exists, but major decision/finding construction still lives in orchestrator body and is not confined to stage modules.
- This is **not** the first repair target unless stability blockers are fixed; immediate priority should stay on active-path correctness and contract alignment.

## 8. FIX NOW / FIX NEXT / LATER
### FIX NOW
- **BATCH-A**: D001, D002.

### FIX NEXT
- **BATCH-B**: D003, D004, D005, D006.

### LATER / DO NOT TOUCH YET
- **BATCH-C**: D007, D008, D009.

## 9. SINGLE STRONGEST NEXT BATCH
**BATCH-A** is the single strongest next repair batch.
- It removes an active route extraction correctness blocker (D001).
- It restores caller/callee signal contract in SURFACE_CONTEXT (D002).
- It is low-to-medium risk and isolated from schema/workflow policy decisions.

---

## Validation answers (explicit)
1. **Full current LINK execution path** is documented in Section 3 from ENTRY through final write.
2. **Exact active-path blockers** are listed in Section 4.
3. **Repeated vs isolated defects** are grouped in Section 6.
4. **Safe co-fix groups** are BATCH-A/BATCH-B/BATCH-C in Sections 8–9.
5. **Defects not to touch next batch** are BATCH-C items in Section 8.
6. **Logic improperly living in `agent.ps1`** is identified in Section 7.
7. **Single strongest next batch** is BATCH-A (Section 9).

### UNRESOLVED — NEEDS RUNTIME EVIDENCE
- Whether any specific production target set currently avoids D001 in practice cannot be proven statically; only runtime runs against concrete sites can confirm impact frequency.
