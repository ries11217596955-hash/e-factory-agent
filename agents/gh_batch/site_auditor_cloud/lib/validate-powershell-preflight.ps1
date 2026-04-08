[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteAuditorRoot = Join-Path $RepoRoot 'agents/gh_batch/site_auditor_cloud'

$explicitTargets = @(
    Join-Path $siteAuditorRoot 'run.ps1'
    Join-Path $siteAuditorRoot 'run_bundle.ps1'
    Join-Path $siteAuditorRoot 'agent.ps1'
)

$libTargets = @()
$libPath = Join-Path $siteAuditorRoot 'lib'
if (Test-Path -LiteralPath $libPath) {
    $libTargets = @(Get-ChildItem -LiteralPath $libPath -Filter '*.ps1' -File | ForEach-Object { $_.FullName })
}

$targets = @($explicitTargets + $libTargets | Sort-Object -Unique)
if ($targets.Count -eq 0) {
    Write-Error 'No SITE_AUDITOR PowerShell files found to validate.'
    exit 1
}

$results = New-Object System.Collections.Generic.List[object]

function New-Issue {
    param(
        [string]$Type,
        [string]$Message,
        [int]$Line,
        [int]$Column
    )

    return [ordered]@{
        type = $Type
        message = $Message
        line = $Line
        column = $Column
    }
}

foreach ($target in $targets) {
    $relativePath = [System.IO.Path]::GetRelativePath($RepoRoot, $target).Replace('\\', '/')

    if (-not (Test-Path -LiteralPath $target)) {
        $results.Add([ordered]@{
            file = $relativePath
            syntax_ok = $false
            token_guard_ok = $false
            issues = @(
                (New-Issue -Type 'missing_file' -Message 'Required file does not exist.' -Line 0 -Column 0)
            )
        })
        continue
    }

    $parseErrors = @()
    $tokens = @()
    [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$parseErrors) | Out-Null

    $issues = New-Object System.Collections.Generic.List[object]
    foreach ($parseError in $parseErrors) {
        $issues.Add((New-Issue -Type 'parser_error' -Message $parseError.Message -Line $parseError.Extent.StartLineNumber -Column $parseError.Extent.StartColumnNumber))
    }

    $logicalTokenMisuse = @($tokens | Where-Object {
        $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Identifier -and $_.Text -match '^(?i:and|or)$'
    })

    foreach ($token in $logicalTokenMisuse) {
        $issues.Add((New-Issue -Type 'logical_token_misuse' -Message "Use -$($token.Text.ToLowerInvariant()) instead of bare '$($token.Text)'." -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber))
    }

    $results.Add([ordered]@{
        file = $relativePath
        syntax_ok = ($parseErrors.Count -eq 0)
        token_guard_ok = ($logicalTokenMisuse.Count -eq 0)
        issues = @($issues)
    })
}

Write-Host 'SITE_AUDITOR PowerShell preflight validation'
Write-Host '-----------------------------------------------------'

$hasFailures = $false
foreach ($result in $results) {
    $status = if ($result.syntax_ok -and $result.token_guard_ok) { 'OK' } else { 'FAIL' }
    if ($status -eq 'FAIL') {
        $hasFailures = $true
    }

    Write-Host "[$status] $($result.file)"
    Write-Host "  syntax: $(if ($result.syntax_ok) { 'OK' } else { 'FAIL' })"
    Write-Host "  token_guard: $(if ($result.token_guard_ok) { 'OK' } else { 'FAIL' })"

    foreach ($issue in $result.issues) {
        $location = if ($issue.line -gt 0) { "$($issue.line):$($issue.column)" } else { 'n/a' }
        Write-Host "  - [$($issue.type)] $location $($issue.message)"
    }
}

$machineSummary = [ordered]@{
    validated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    repo_root = $RepoRoot
    overall_status = if ($hasFailures) { 'FAIL' } else { 'PASS' }
    files = @($results)
}

Write-Host '-----------------------------------------------------'
Write-Host ($machineSummary | ConvertTo-Json -Depth 8)

if ($hasFailures) {
    Write-Error 'PowerShell preflight validation failed.'
    exit 1
}

Write-Host 'PowerShell preflight validation passed.'
exit 0
