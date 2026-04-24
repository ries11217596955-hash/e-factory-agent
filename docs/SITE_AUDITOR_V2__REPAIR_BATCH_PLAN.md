# SITE_AUDITOR_V2 Repair Batch Plan (Audit-Derived)

## A. FIX NOW (current active-path blockers)

### Batch ID: BATCH-A
- **Exact files**
  - `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - `agents/site_auditor_v2/agent.ps1`
- **Exact defect class**
  - `active_path_route_extraction`
  - `return_contract_mismatch`
- **Defects included**
  - SAV2-D001
  - SAV2-D002
- **Why grouped together**
  - Both defects are in the active LINK correctness corridor before dependable finding synthesis.
- **Expected risk**
  - Medium (touches extraction and downstream signal use).
- **Acceptance criteria**
  - Relative hrefs (non-root) are resolved through a single safe resolution path and can enter route candidates when internal.
  - SURFACE_CONTEXT uses a guaranteed producer field set; `first_screen_text_length` is present and non-implicit.
  - No regression in existing route contract checks.
- **Why not to mix with other batches**
  - Mixing with schema/workflow updates obscures runtime correctness validation for core LINK path.

## B. FIX NEXT (important but not current blocker)

### Batch ID: BATCH-B
- **Exact files**
  - `agents/site_auditor_v2/agent.ps1`
  - `agents/site_auditor_v2/contracts/run_report.schema.json`
  - `agents/site_auditor_v2/contracts/failure_summary.schema.json`
- **Exact defect class**
  - `trace_localization_gap`
  - `schema_contract_drift`
- **Defects included**
  - SAV2-D003
  - SAV2-D004
  - SAV2-D005
  - SAV2-D006
- **Why grouped together**
  - All items are contract/reportability hardening and do not require changing crawl-selection semantics.
- **Expected risk**
  - Low-to-medium.
- **Acceptance criteria**
  - CAPTURE stage has deterministic stage trace marker parity with other critical stages.
  - run_report schema validates current active output shape for page_verdicts/findings.
  - failure_summary schema validates current failure payload structure.
- **Why not to mix with other batches**
  - Must be validated independently from extraction logic to isolate contract drift resolution.

## C. LATER / DO NOT TOUCH YET

### Batch ID: BATCH-C
- **Exact files**
  - `agents/site_auditor_v2/modules/stage_route_keys.ps1`
  - `agents/site_auditor_v2/modules/stage_link_fetch.ps1`
  - `.github/workflows/site-auditor-v2-link.yml`
- **Exact defect class**
  - `module_internal_drift`
  - `orchestrator_module_boundary`
  - `runtime_contract_gap`
- **Defects included**
  - SAV2-D007
  - SAV2-D008
  - SAV2-D009
- **Why grouped together**
  - These are structural consistency/runtime-validation coverage improvements, not immediate active-path crash blockers.
- **Expected risk**
  - Medium (especially workflow/runtime changes).
- **Acceptance criteria**
  - Duplicate helper definitions removed with no behavior drift.
  - Href resolution logic is single-sourced (module helper consumed by extraction loop).
  - Runtime validation strategy explicitly covers PS5.1 contract (policy-dependent).
- **Why not to mix with other batches**
  - Workflow/policy changes should be reviewed separately from functional path stabilization.
