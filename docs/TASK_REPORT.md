## Summary
Updated `site_auditor_v2` to treat visual capture as an optional capability. Capture failures (including missing Playwright/module errors) now degrade execution instead of failing the run, while explicitly marking reduced confidence and no visual evidence.
Follow-up fix: report-layer decision synthesis now understands `NO_VISUAL_EVIDENCE` limitations and emits capture-recovery guidance instead of route-budget guidance when capture is unavailable.

## Changed files
- agents/site_auditor_v2/agent.ps1
- agents/site_auditor_v2/modules/report_layer.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint/orchestrator: `agents/site_auditor_v2/agent.ps1`
- Optional capture tool invocation path (unchanged): `agents/site_auditor_v2/tools/capture_visuals.mjs`
- Run output artifacts (unchanged paths): `<run output root>/RUN_REPORT.json`, `<run output root>/visual_manifest.json`, `<run output root>/screenshots/`

## Risks/blockers
- Full end-to-end run in a Codespaces environment without Playwright was not executed here; behavior was validated through static code-path review and PowerShell parse checks.
- Degradation path intentionally marks capture unavailable as a limitation and keeps non-capture audit stages active, but exact final status labels still depend on existing downstream status synthesis logic.
