# PHASE-2 STATUS

This patch materializes the canonical layout that was previously only declared in README.

Verified intent
- active agents: GH_BATCH and SITE_AUDITOR_AGENT
- source-of-truth should live under agents/
- release packages should live under releases/ only

What this closes
- README vs archive mismatch
- missing canonical agent folders
- missing releases/ placeholders

What still remains manual
- deleting old root files and legacy placeholder folders
- runtime verification of either agent
