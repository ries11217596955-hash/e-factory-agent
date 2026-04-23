## Summary
- Implemented PACK 3 systemization in `SITE_AUDITOR_V2`: high-signal findings are now grouped into deterministic micro-clusters (`PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, `NO_ACTION_PATH`, `BROKEN_ROUTE`) when at least 2 routes are affected.
- Added cluster metrics for each qualifying cluster: affected route count, up to 5 route examples, and share of checked pages.
- Added a `system_problem` layer (when applicable) that maps clustered issues to system-level problem types (`VALUE_STRUCTURE`, `VALUE_CLARITY`, `ACTION_PATH`) with scope and severity.
- Added decision override logic so `decision_summary` prioritizes system-level conclusions/actions when a qualifying system problem exists; otherwise it falls back to existing page-level behavior.
- Updated HUMAN_REPORT generation so it starts with the system problem statement and then provides 1–2 concrete route examples.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added `Get-SystemProblemMapping` for deterministic issue→system-problem translation.
  - Added `micro_clusters` generation with count, route examples, and share-of-pages metrics.
  - Added `system_problem` synthesis with severity and scope rules.
  - Added decision override behavior to drive `decision_summary` from system problem when present.
  - Added system-level action mapping:
    - VALUE domains → rewrite first screen across key pages.
    - ACTION_PATH domain → add consistent CTA across key pages.
  - Updated HUMAN_REPORT wording and supporting examples to present system-level framing first.
- `docs/TASK_REPORT.md`
  - Replaced content for PACK 3 systemization report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Route discovery unchanged.
- Screenshot engine unchanged (`agents/site_auditor_v2/tools/capture_visuals.mjs` untouched).
- Ownership logic unchanged (ownership mode and owned/external action routing preserved).
- Confidence logic unchanged at signal level (still evidence-gated high-signal findings); PACK 3 adds only post-finding system aggregation.

## Risks/blockers
- `BROKEN_ROUTE` clusters are tracked in `micro_clusters`, but no system-problem mapping is applied for them by design; decisions may remain page-level if only broken-route clustering is present.
- System-problem severity escalates to `HIGH` when 3+ pages are affected or major page types (`HOME`, `DECISION`, `TOOL`) are included; this can change top-level recommendations compared with single-finding prioritization.
- External-ownership recommendations remain benchmarking-oriented; operators expecting direct remediation phrasing for external sites should align with ownership constraints.
- No blockers encountered.

### Clustering logic
- Eligible issue types: `PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, `NO_ACTION_PATH`, `BROKEN_ROUTE`.
- Cluster threshold: at least 2 unique affected routes.
- Per-cluster metrics emitted:
  - `count`
  - `routes` (max 5)
  - `share_of_checked_pages` (count / checked routes)

### System problem rules
- Mapping rules:
  - `PROCESS_FIRST` → `VALUE_STRUCTURE`
  - `NO_VALUE_FIRST_SCREEN` → `VALUE_CLARITY`
  - `NO_ACTION_PATH` → `ACTION_PATH`
- Severity:
  - `HIGH` when affected routes >= 3 OR major pages are affected.
  - `MEDIUM` when affected routes = 2.
  - `LOW` is ignored (not emitted as system problem).
- Decision override:
  - If `system_problem` exists, `decision_summary` uses system-level issue/reasoning/action.
  - If no qualifying mapped cluster exists, existing page-level logic remains active.

### Rollback
1. Remove `Get-SystemProblemMapping` from `agents/site_auditor_v2/agent.ps1`.
2. Remove micro-cluster synthesis and restore `report.micro_clusters` to empty output.
3. Remove `system_problem` generation and decision override branches.
4. Restore HUMAN_REPORT main-finding logic to page-level-first wording.
5. Restore previous `docs/TASK_REPORT.md` content for PACK 2.
