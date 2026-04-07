SITE_AUDITOR mode split fix

Changed files:
- .github/workflows/site-auditor-fixed-list.yml
- agents/gh_batch/site_auditor_cloud/run.ps1
- agents/gh_batch/site_auditor_cloud/agent.ps1
- agents/gh_batch/site_auditor_cloud/capture.mjs

What this fixes:
- manual run audits target_repo instead of collapsing into live-only mode
- zip run audits extracted ZIP content instead of collapsing into live-only mode
- live screenshots are side evidence for REPO mode, not the source of truth
- artifacts are always produced: REPORT.txt, JSONs, DONE.ok, outbox zip
