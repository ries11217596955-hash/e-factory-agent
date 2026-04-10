# TASK_REPORT

## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/AGENT_PS1_DEEP_AUDIT.md`
- `docs/TASK_REPORT.md` (pre-task state)
- `agents/gh_batch/site_auditor_cloud/agent.ps1`

## TASK
- `SITE_AUDITOR — surgical fix for PQ7_pattern_summary_build hashtable merge failure`.

## REPOSITORY SCOPE (Allowed / Forbidden)
- Allowed:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `docs/TASK_REPORT.md`
- Forbidden (respected):
  - `.github/workflows/**`
  - unrelated agents
  - other runtime lanes
  - giant rewrite / broad refactor
  - output contract redesign
  - touching already-passing `ROUTE_NORMALIZATION` / `ROUTE_MERGE`

## MODE
- PR-FIRST
- SURGICAL RUNTIME FIX

## REQUIREMENTS
- Identify exact failing combine path inside `Build-SitePatternSummary`.
- Replace fragile pattern output merge with deterministic `object[]` combination (no hashtable arithmetic).
- Improve local PQ7 forensic fidelity with combine operand and type/count details.
- Run strongest available parse/structural validation and report parser execution status.

## REPORTING
- Includes repository-mandated sections and operator-required runtime forensics notes.

## SUMMARY
- Confirmed the exact PQ7 failure site was the `@($repeatedPatternsOutput + $isolatedPatternsOutput)` combine expression in `Build-SitePatternSummary`.
- Replaced the combine path with deterministic array materialization and explicit list-based append (`List[object]`), then converted once to final `object[]`.
- Added local PQ7 sub-operation labels (`PQ7a`, `PQ7b`, `PQ7c`) to isolate prepare/combine/dominant-selection phases.
- Added PQ7-specific forensic capture for exact combine left/right operands plus counts/types for repeated/isolated outputs.
- Preserved output schema exactly (`repeated_patterns`, `isolated_patterns`, `repeated_pattern_count`, `isolated_pattern_count`, `systemic`, `dominant_pattern`).

## CHANGED FILES
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## ROOT CAUSE OF PQ7 FAILURE
- The previous combine expression used `+` directly between two values that can resolve to hashtable-like/dictionary-shaped objects in edge cases:
  - `@($repeatedPatternsOutput + $isolatedPatternsOutput)`
- In PowerShell, `+` on hashtable-like values invokes hashtable-add semantics, producing the runtime error:
  - `A hash table can only be added to another hash table.`

## EXACT SECTION REPAIRED
- Function: `Build-SitePatternSummary`.
- Repaired path:
  - Removed fragile merge expression at the pattern summary combine point.
  - Added deterministic operand materialization (`Convert-ToPageQualityObjectArray` for each side).
  - Combined via explicit append into `System.Collections.Generic.List[object]`, then output as `object[]`.
  - Dominant pattern selection now iterates deterministic combined array.
- Forensics enhancement:
  - Added `repeated_patterns_output_count`, `isolated_patterns_output_count`, `repeated_patterns_output_type`, `isolated_patterns_output_type`.
  - Added PQ7 left/right operand remapping in catch for combine/dominant sub-operations.

## VALIDATION EXECUTED
- Targeted code inspection and line verification:
  - `rg -n "function Build-SitePatternSummary|PQ7[a-c]_pattern_summary|repeatedPatternsOutput|isolatedPatternsOutput|combinedPatternList|combinedPatterns|A hash table can only be added" agents/gh_batch/site_auditor_cloud/agent.ps1`
- PowerShell parser availability check:
  - `command -v pwsh || command -v powershell || true`

PowerShell parse status:
- **PowerShell parse did not run in this container** because neither `pwsh` nor `powershell` is installed.

## REMAINING RISKS
- End-to-end runtime validation is still required in a PowerShell-capable runner.
- If a subsequent failure appears, it may occur in downstream consumers of `pattern_summary`, not in the repaired combine path.

## EXPECTED NEXT RUNTIME STATE
- `PAGE_QUALITY_BUILD` should no longer fail due to hashtable-addition semantics in `PQ7_pattern_summary_build`.
- If PQ7 fails again, forensics should identify exact sub-operation (`PQ7a`/`PQ7b`/`PQ7c`) and include combine operand counts/types.
- Upstream passing lanes (`ROUTE_NORMALIZATION`, `ROUTE_MERGE`) remain untouched.

## Summary
- Implemented a narrow PQ7 repair for deterministic pattern-array merging and improved PQ7-local forensics.

## Changed files
- `agents/gh_batch/site_auditor_cloud/agent.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Unchanged:
  - `agents/gh_batch/site_auditor_cloud/agent.ps1`
  - `agents/gh_batch/site_auditor_cloud/run.ps1`
  - `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`

## Risks/blockers
- PowerShell executable is unavailable in this container; parse/runtime confirmation must occur in CI or an operator PowerShell environment.
