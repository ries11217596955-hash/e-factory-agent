## Summary
Added a diagnostic-only offline forensic harness for DECISION_BUILD without altering production entrypoints or decision business logic.
- Added `decision_build_forensics.ps1` under tools to load snapshot input, import decision modules, execute major decision-build sub-steps with typed diagnostics, and run `Build-DecisionLayer` under controlled try/catch.
- Harness emits a dedicated diagnostic artifact containing per-step variable type metadata and failure payload (`failing_step`, exact exception, last label, and type dump).
- Added a minimal documented snapshot example file defining required fields for forensic execution.

## Changed files
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`
- `agents/gh_batch/site_auditor_cloud/tools/decision_build_snapshot.example.json`
- `docs/TASK_REPORT.md`

## Moved files/folders
- No files/folders moved.

## Current entrypoints/paths
- Production entrypoints unchanged: `agents/gh_batch/site_auditor_cloud/agent.ps1`, `agents/gh_batch/site_auditor_cloud/run.ps1`.
- New diagnostic-only entrypoint: `agents/gh_batch/site_auditor_cloud/tools/decision_build_forensics.ps1`.
- Diagnostic snapshot example: `agents/gh_batch/site_auditor_cloud/tools/decision_build_snapshot.example.json`.

## Risks/blockers
- The harness relies on module function contracts remaining stable; if module signatures change, snapshot shape may need to be adjusted.
- Forensics reproduces decision-build path locally, but cannot emulate external cloud/runtime dependencies outside snapshot truth.
