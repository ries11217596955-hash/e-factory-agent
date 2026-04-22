## Summary
- Added strict LINK-mode route contract validation in `site_auditor_v2` so primary route identity is enforced as canonical path-only across runtime artifacts.
- Added fail-fast behavior for route contract breaches: run status is forced to `FAIL`, `RUN_REPORT` is marked with route contract failure, and `failure_summary.json` is written with `fail_reason = ROUTE_CONTRACT_BREACH` plus violation details.
- Added explicit `route_contract` section in `RUN_REPORT` with `status`, `primary_key_format`, and collected `violations`.
- Added deterministic regression script under `tests/` to validate output folders/fixtures against the same route-contract surfaces.
- Kept scope bounded to the requested files and did not add capabilities, depth expansion, or scoring/decision redesign.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
- `tests/check_route_contract.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint remains `agents/site_auditor_v2/agent.ps1`.
- New regression check: `tests/check_route_contract.ps1 -OutputFolder <artifact_folder>`.

## Risks/blockers
- Regression script validates generated artifacts, not live crawl behavior by itself; it must be run against a produced output folder or fixture bundle.
- Existing historical artifacts that still contain URL-style primary route keys will now fail the contract check by design.

## Route contract added
- Primary route fields must be non-empty, start with `/`, contain no scheme/host, no fragment, no query, and normalized trailing slash (except root `/`).
- Enforced surfaces:
  - `RUN_REPORT.selected_routes[*].route`
  - `RUN_REPORT.page_verdicts[*].route`
  - `RUN_REPORT.run_budget.overflow_route_details[*].route`
  - `visual_manifest.pages[*].route`
  - `ROUTES_SUMMARY.routes[*].normalized_route`
- Secondary absolute URL fields remain allowed (`source_url`, `url`).

## Failure behavior
- Any route contract violation now forces non-PASS completion (`FAIL`) and sets run summary to `ROUTE_CONTRACT_BREACH`.
- `failure_summary.json` now includes:
  - `fail_reason`
  - `route_contract_violations[]` entries with exact `artifact_path`, `field_path`, and `offending_value`.

## How to run the regression check
- Against any generated output directory:
  - `pwsh -File tests/check_route_contract.ps1 -OutputFolder agents/site_auditor_v2/output/<run_id>`
- Exit code `0` => contract OK, exit code `1` => `ROUTE_CONTRACT_BREACH` with JSON violation list.
