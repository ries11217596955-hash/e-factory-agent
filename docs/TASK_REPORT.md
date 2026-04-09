## INSTRUCTION_FILES_READ
- `AGENTS.md`
- `docs/REPO_LAYOUT.md`
- `docs/TASK_REPORT.md` (pre-change)

## Summary
- Applied a syntax-only hotfix in `agents/gh_batch/site_auditor_cloud/run_bundle.ps1` for PowerShell string interpolation in the operator-report block.
- Root cause: the interpolation form `"$failureStage: $evaluationError"` caused a parse error because `:` immediately after a variable reference is invalid in this context.
- Replaced with the PowerShell-safe braced variable form: `"${failureStage}: $evaluationError"`.
- Confirmed no logic expansion and no changes outside the allowed scope.

## Root cause
- Offending expression used unbraced interpolation with a trailing colon:
  - `"$failureStage: $evaluationError"`
- PowerShell treated `:` as part of an invalid variable reference, producing parse failure.

## Changed files
- `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- `docs/TASK_REPORT.md`

## Moved files/folders
- None.

## Current entrypoints/paths
- Entrypoint unchanged: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`.
- No workflow, runtime-flow, or bundle-contract redesign changes.

## Exact edited line
- File: `agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Before:
  - `$detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "$failureStage: $evaluationError" } else { $failureStage }`
- After:
  - `$detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "${failureStage}: $evaluationError" } else { $failureStage }`

## Before / After snippet
- Before:
```powershell
if ($pageQualityStatus -eq 'NOT_EVALUATED') {
    $detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "$failureStage: $evaluationError" } else { $failureStage }
    ...
}
```
- After:
```powershell
if ($pageQualityStatus -eq 'NOT_EVALUATED') {
    $detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "${failureStage}: $evaluationError" } else { $failureStage }
    ...
}
```

## Validation method used
- Verified replacement with targeted search:
  - `rg -n "\$failureStage: \$evaluationError|\$\{failureStage\}: \$evaluationError|failureStage" agents/gh_batch/site_auditor_cloud/run_bundle.ps1`
- Checked immediately adjacent block for same `"$var: ..."` interpolation risk pattern.
- Performed static parse validation with PowerShell parser:
  - `pwsh -NoLogo -NoProfile -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("agents/gh_batch/site_auditor_cloud/run_bundle.ps1",[ref]$tokens,[ref]$errors) | Out-Null; if($errors.Count -eq 0){"PARSE_OK"} else {$errors | ForEach-Object { $_.Message }; exit 1 }'`

## Risks/blockers
- This is a syntax hotfix only; runtime behavior beyond parse restoration was not expanded or newly claimed.
- No blockers encountered in applying or statically validating this change.
