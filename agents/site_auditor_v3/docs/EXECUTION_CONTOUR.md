# EXECUTION CONTOUR — SITE_AUDITOR_V3

## Purpose
Define the current Windows operator execution contour for `SITE_AUDITOR_V3` work.
This file prevents shell/tool confusion during runtime verification and diagnostics.

---

## Default operator contour

### PowerShell
Use PowerShell as the Windows operator shell for:
- filesystem paths under `C:\...`
- environment variables such as `$env:REQUEST_PATH`
- writing or replacing small local files
- checking `git status`, `git diff`, installed tools, and Windows paths
- invoking Git Bash explicitly by absolute path when a `.sh` wrapper must run

### Git Bash
Use Git Bash only when the repository contract is Bash-native, for example:
- `agents/site_auditor_v3/tests/run_and_validate.sh`
- bash wrappers and shell validation flows

On the current Windows contour, invoke the actual Git Bash executable explicitly:

```powershell
$gitBash = "C:\Program Files\Git\bin\bash.exe"
& $gitBash -lc './agents/site_auditor_v3/tests/run_and_validate.sh'
```

Do **not** rely on bare:

```powershell
bash -lc '...'
```

because on this workstation it can resolve to WSL Bash instead of Git Bash.

### Python
Use Python for:
- JSON inspection
- structured artifact comparison
- ledger/report analytics
- small helper scripts where PowerShell would be fragile

Avoid large interactive Python here-doc blocks inside PowerShell when a shorter PowerShell block or a temporary `.py` helper is safer.

Current Git Bash compatibility note:
- `python3` must resolve to a real Python executable, not a Windows Store alias stub.

### Node
Use Node / npm only for the layers that own it:
- capture tooling
- browser automation / Playwright-style flows
- site/JS-side utilities

Do not pull Node into ledger/report cleanup steps unless the target code already depends on Node.

---

## Tool selection law

Choose the tool by **operation owner**, not by convenience:

| Operation owner | Default tool |
|---|---|
| Windows path/env/file control | PowerShell |
| `.sh` wrapper execution | Git Bash via explicit absolute path |
| JSON/ledger/report analytics | Python when needed |
| capture/site/browser JS layer | Node/npm |
| bounded code patch with known root cause | direct terminal patch or Codex, whichever is safer |

---

## Agent verification sequence

For runtime verification:
1. prepare request input
2. run wrapper through explicit Git Bash path
3. read `RUN_REPORT.json`
4. verify validator output
5. inspect runpack / report evidence
6. only then decide next move

---

## Failure interpretation

If a wrapper stops before agent execution, classify the failure by layer first:
- shell line ending / interpreter issue
- missing executable (`pwsh`, `python3`, etc.)
- invalid or missing request file
- actual agent/runtime defect

Do not call an agent defect before the wrapper reaches agent execution.
