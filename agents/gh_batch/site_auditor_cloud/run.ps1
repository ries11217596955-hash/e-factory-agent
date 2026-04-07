param(
    [string]$MODE
)

$resolvedMode = if ($PSBoundParameters.ContainsKey('MODE') -and -not [string]::IsNullOrWhiteSpace($MODE)) {
    $MODE
} elseif (-not [string]::IsNullOrWhiteSpace($env:FORCE_MODE)) {
    $env:FORCE_MODE
} else {
    'REPO'
}

Write-Host "SITE_AUDITOR resolved mode: $resolvedMode"

& (Join-Path $PSScriptRoot 'agent.ps1') -MODE $resolvedMode
exit $LASTEXITCODE
