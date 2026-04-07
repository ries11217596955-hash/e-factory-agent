# APPLY NOTE — AGENT REPO CLEANUP PATCH

Mode: DEVELOPMENT
Intent: convert repo from mixed archive storage into a cleaner source-oriented agent repo.

What this patch does:
- creates canonical source folders for the two active agents
- materializes source-of-truth files under `agents/`
- adds repo layout / cleanup guidance under `docs/`
- prepares `releases/` as the only intended place for future ZIP packages
- updates root README and repo manifest

What this patch does not do automatically:
- delete old ZIP files already sitting in repo root
- verify runtime PASS for either agent
- rewrite historical release archives

After upload:
- keep `agents/` as source of truth
- stop adding new release ZIP files to repo root
- use `DELETE_ROOT_FILES.txt` as the cleanup checklist for the next commit
