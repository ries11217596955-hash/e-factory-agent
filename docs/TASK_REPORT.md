## Summary
- Implemented PACK 5 context normalization in `SITE_AUDITOR_V2` by introducing normalized surface types: `MEDIA_HOME`, `MEDIA_SECTION`, `ARTICLE`, `LANDING`, `DECISION`, `TOOL`, `DIRECTORY`, `UNKNOWN`.
- Added deterministic surface heuristics based on URL/title patterns, headline/list density, repeated link block ratio, and timestamp/news-listing patterns (no LLM inference).
- Added a surface expectation model and applied it to findings generation so `NO_VALUE_FIRST_SCREEN`, `PROCESS_FIRST`, and `NO_ACTION_PATH` are emitted only when context-valid.
- Added false-positive guards for media streams, article pages, and directory/listing surfaces to suppress inappropriate first-screen/value/action defects.
- Added system-problem quality lock behavior and report wording/context updates so decisions and human reports stay aligned with context-valid findings.

## Changed files
- `agents/site_auditor_v2/agent.ps1`
  - Added normalized surface classifier (`Get-NormalizedSurfaceType`) using bounded heuristics.
  - Added expectation model (`Get-SurfaceExpectation`) per normalized surface type.
  - Updated page route extraction signals to include:
    - `headline_count`
    - `article_list_count`
    - `repeated_link_block_ratio`
    - `has_timestamp_patterns`
  - Updated surface mapping to retain normalized surface names in findings/verdicts.
  - Rebuilt findings conditions with context-aware gating:
    - media guard
    - article guard
    - directory guard
    - action/value expectation gating by surface type
  - Updated system-problem synthesis to rely on context-valid HIGH findings and avoid strong synthesis from false-positive-prone surface clusters.
  - Updated human report payload text with brief surface context explanation and clean-scope wording: `No confirmed system-level defect was established in the checked scope.`

- `docs/TASK_REPORT.md`
  - Replaced with PACK 5 implementation report.

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/site_auditor_v2/agent.ps1`.
- Route discovery core unchanged.
- Screenshot engine core unchanged.
- Decision spine structure preserved (logic inputs tightened to context-valid findings).
- Bilingual report layout structure preserved (payload wording/context adjusted only).

## Risks/blockers
- PowerShell runtime validation is blocked in this environment (`pwsh` unavailable), so runtime execution checks could not be performed.
- Heuristics are deterministic but may need threshold tuning on edge-case hybrid surfaces.
- Stronger guards may suppress borderline findings on ambiguous pages, favoring false-positive reduction over aggressive detection.
- No protected paths were touched.

## New surface types
- `MEDIA_HOME`
- `MEDIA_SECTION`
- `ARTICLE`
- `LANDING`
- `DECISION`
- `TOOL`
- `DIRECTORY`
- `UNKNOWN`

## Expectation model
- `MEDIA_HOME` / `MEDIA_SECTION`
  - value-first slogan optional
  - first screen can be editorial/content stream
  - no automatic CTA/value defect on listing behavior
- `ARTICLE`
  - headline + lead can satisfy first-screen value
  - CTA absence is not automatically defective
- `DIRECTORY`
  - structured listing/choice can satisfy value intent
  - CTA absence is not automatically defective
- `LANDING` / `DECISION` / `TOOL`
  - retain strict value-first and clear action-path expectations

## Context-aware defect rules
- `NO_VALUE_FIRST_SCREEN`
  - allowed primarily where `expects_value_first = true`
  - suppressed for media/article/directory contexts when listing/lead signals are present
- `PROCESS_FIRST`
  - allowed for non-media contexts where process framing appears before value
  - suppressed for normal media stream/listing surfaces
- `NO_ACTION_PATH`
  - allowed only where `expects_action_path = true`
  - suppressed on media/article/directory surfaces
- `BROKEN_ROUTE`
  - unchanged high-signal route reachability rule

## False-positive guards
- MEDIA guard:
  - listing/timestamp/headline stream patterns do not default to `NO_VALUE_FIRST_SCREEN`
- ARTICLE guard:
  - article-like lead coverage suppresses first-screen CTA/value defect assumptions
- DIRECTORY guard:
  - structured choice/listing patterns suppress value/action false positives

## Rollback instructions by file/block
1. `agents/site_auditor_v2/agent.ps1`
   - Remove `Get-NormalizedSurfaceType` and `Get-SurfaceExpectation` functions.
   - Restore prior page classification behavior (`HOME/HUB/...`) in route extraction block.
   - Remove added route signals (`headline_count`, `article_list_count`, `repeated_link_block_ratio`, `has_timestamp_patterns`).
   - Restore pre-PACK5 finding rules block (non-context-gated `PROCESS_FIRST`, `NO_VALUE_FIRST_SCREEN`, `NO_ACTION_PATH`).
   - Restore pre-PACK5 system-problem cluster selection without false-positive-prone surface lock.
   - Restore pre-PACK5 human report wording/context lines.
2. `docs/TASK_REPORT.md`
   - Restore previous content from git history.
