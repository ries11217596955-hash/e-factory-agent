## INSTRUCTION_FILES_READ
- AGENTS.md (repo root)
- docs/README.md
- docs/REPO_LAYOUT.md
- docs/TASK_REPORT.md (previous report baseline)
- User task specification: SITE_AUDITOR — ROUTE_NORMALIZATION EVIDENCE-FIRST FORENSIC PASS (P0)

## FAILURE_ARTIFACT_PATH
- reports/route_normalization_debug.json

## EXACT_FUNCTION
- Safe-Get

## EXACT_EXPRESSION
- $candidateKeyText -eq $keyText

## LEFT_TYPE
- System.String (post-normalization compare boundary)

## RIGHT_TYPE
- System.String (post-normalization compare boundary)

## SAMPLE_VALUES
- left_value_sample: derived from dictionary entry key string cast (`[string]$candidateKey`)
- right_value_sample: lookup key string (`[string]$Key`)
- Note: exact runtime samples require a failing rerun; this environment cannot execute PowerShell to produce a new failure artifact.

## FIX_APPLIED
- Kept scope locked to ROUTE_NORMALIZATION direct helper path in `Safe-Get` and forensic writer path only.
- Updated forensic payload schema to include required top-level fields:
  - failure_stage
  - function_name
  - expression
  - left_type
  - right_type
  - left_value_sample
  - right_value_sample
  - context_keys
  - route_path_if_available
  - stack_hint_if_available
- Added stack hint capture from failing comparison/cast catch blocks.
- Ensured ROUTE_NORMALIZATION catch writes `reports/route_normalization_debug.json` even when detailed forensics were not populated yet (fallback payload with known fields).

## VALIDATION_RESULT
- Static validation only (file diff and schema/path verification).
- Runtime validation blocked: `pwsh`/`powershell` is unavailable in this container, so no new bundle execution could be performed.

## NEXT_BLOCKER_IF_ANY
- Missing PowerShell runtime prevents generating fresh forensic evidence from a live failing run.

## Summary
- Implemented evidence-first forensic payload hardening for ROUTE_NORMALIZATION failure capture.
- Added guaranteed artifact fallback creation path for ROUTE_NORMALIZATION stage failures.
- Did not touch diagnosis, contradiction, maturity/readiness, executive/operator, remediation package, product closeout, or screenshot layers.

## Changed files
- agents/gh_batch/site_auditor_cloud/agent.ps1
- docs/TASK_REPORT.md

## Moved files/folders
- None.

## Current entrypoints/paths
- agents/gh_batch/site_auditor_cloud/run.ps1
- agents/gh_batch/site_auditor_cloud/agent.ps1
- agents/gh_batch/site_auditor_cloud/run_bundle.ps1

## Risks/blockers
- Exact live failing values remain pending until runtime can be executed with PowerShell.
- If failure persists, `reports/route_normalization_debug.json` should now contain required evidence keys even when failure occurs early.
