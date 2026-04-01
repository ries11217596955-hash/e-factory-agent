# GH_BATCH

Status: active packaged unit
Source of truth for this repo: `agents/gh_batch/`
Entrypoint: `RUN_BATCH.ps1`

Purpose:
- patch-batch intake
- guarded repo update flow
- preview / what-if mode
- post-commit verification

Verified package facts:
- package contains `RUN_BATCH.ps1`
- package contains `agent.config.json`
- package contains `.state/processed_sha256.txt`
- README documents safe auto-fix, plaintext guard, and RUN_REPORT JSON support

Boundary:
- packaging presence does not equal verified runtime PASS
- release ZIPs should not be treated as source of truth once files are materialized here
