SITE_AUDITOR_AGENT v3.0.4

Install
1. Put your GitHub token into .state\github_token.txt
2. Review agent.config.json
3. Review site.target.json
4. Run .\CREATE_SHORTCUT.ps1
5. Start the agent via the desktop shortcut

Output
- ZIP report appears in outbox\

Notes
- The agent fetches the repo via GitHub API ZIP.
- Git is not required.
- The shortcut runs run.ps1 through PowerShell.
- For diagnostics you can run .\run.ps1 directly from PowerShell.


v3.1.2 FULLFIX:
- Adds 11_HOW_TO_FIX.json with repair-oriented findings.
