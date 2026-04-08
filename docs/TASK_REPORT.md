## Summary
- Upgraded core page experience from passive reading to immediate action by adding outcome-first hero copy, an instant action block, an execution checklist, a result promise, a before/after example, and a search-fallback route block at the shared article template level.
- Upgraded the global hubs landing page with required activation blocks: “Start here if you are new,” “Fastest result path,” and “Top 3 actions,” plus explicit no-results search fallback routes.
- Upgraded the Amazon hub with action-first startup guidance, quick-start pathing, tool-page quick-start framing (use case + expected outcome), and explicit before/after scenario value.
- Upgraded reusable tool content block from generic filler to concrete, execution-level guidance including one-step instant action and observable checklist outcomes.
- Estimated actionable-level coverage: ~55% of content pages upgraded directly via shared template + hub-page updates (52 of 94 markdown pages, inferred from layout usage and targeted hub updates).

## Changed files
- `_foreign/webops/_includes/article.njk`
- `_foreign/webops/hubs/index.njk`
- `_foreign/webops/hubs/amazon-ai/index.njk`
- `_foreign/webops/_includes/partials/tool_block.njk`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Shared article rendering path for post-style pages: `_foreign/webops/_includes/article.njk`
- Hub landing page entry: `_foreign/webops/hubs/index.njk` (permalink `/hubs/`)
- Amazon hub entry: `_foreign/webops/hubs/amazon-ai/index.njk`
- Reusable tool recommendation block: `_foreign/webops/_includes/partials/tool_block.njk`

## Risks/blockers
- Search fallback is implemented as content-level fallback guidance/routes; runtime JS empty-state behavior could still require asset-level updates if dynamic search UI is defined outside this repository snapshot.
- “Every page” was addressed through shared templates and key hub surfaces; pages using non-article/non-hub layouts may need separate follow-up for 100% uniformity.
- No runtime or deployment logic was modified (intentional, to stay inside safe content scope).
