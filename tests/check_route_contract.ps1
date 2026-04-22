[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PrimaryRouteValue {
    param(
        [string]$Value
    )

    $routeValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($routeValue)) { return 'empty' }

    $trimmed = $routeValue.Trim()
    if (-not $trimmed.StartsWith('/')) { return 'must_start_with_slash' }
    if ($trimmed -match '^[a-z][a-z0-9+\-.]*://') { return 'contains_scheme' }
    if ($trimmed -match '#') { return 'contains_fragment' }
    if ($trimmed -match '\?') { return 'contains_query' }
    if ($trimmed -match '^//') { return 'contains_host_like_prefix' }
    if (($trimmed.Length -gt 1) -and $trimmed.EndsWith('/')) { return 'trailing_slash_not_normalized' }

    return ''
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required artifact missing: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$runReportPath = Join-Path $OutputFolder 'RUN_REPORT.json'
$routesSummaryPath = Join-Path $OutputFolder 'ROUTES_SUMMARY.json'
$visualManifestPath = Join-Path $OutputFolder 'visual_manifest.json'

$runReport = Read-JsonFile -Path $runReportPath
$routesSummary = Read-JsonFile -Path $routesSummaryPath
$visualManifest = Read-JsonFile -Path $visualManifestPath

$violations = [System.Collections.Generic.List[object]]::new()

function Add-Violation {
    param(
        [string]$Artifact,
        [string]$Field,
        [string]$Value,
        [string]$Reason
    )
    $violations.Add([ordered]@{
        artifact_path = $Artifact
        field_path = $Field
        offending_value = $Value
        reason = $Reason
    })
}

$selected = @($runReport.selected_routes)
for ($i = 0; $i -lt $selected.Count; $i++) {
    $reason = Test-PrimaryRouteValue -Value ([string]$selected[$i].route)
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Add-Violation -Artifact 'RUN_REPORT.json' -Field ("selected_routes[{0}].route" -f $i) -Value ([string]$selected[$i].route) -Reason $reason
    }
}

$verdicts = @($runReport.page_verdicts)
for ($i = 0; $i -lt $verdicts.Count; $i++) {
    $reason = Test-PrimaryRouteValue -Value ([string]$verdicts[$i].route)
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Add-Violation -Artifact 'RUN_REPORT.json' -Field ("page_verdicts[{0}].route" -f $i) -Value ([string]$verdicts[$i].route) -Reason $reason
    }
}

$overflow = @($runReport.run_budget.overflow_route_details)
for ($i = 0; $i -lt $overflow.Count; $i++) {
    $reason = Test-PrimaryRouteValue -Value ([string]$overflow[$i].route)
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Add-Violation -Artifact 'RUN_REPORT.json' -Field ("run_budget.overflow_route_details[{0}].route" -f $i) -Value ([string]$overflow[$i].route) -Reason $reason
    }
}

$pages = @($visualManifest.pages)
for ($i = 0; $i -lt $pages.Count; $i++) {
    $reason = Test-PrimaryRouteValue -Value ([string]$pages[$i].route)
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Add-Violation -Artifact 'visual_manifest.json' -Field ("pages[{0}].route" -f $i) -Value ([string]$pages[$i].route) -Reason $reason
    }
}

$routes = @($routesSummary.routes)
for ($i = 0; $i -lt $routes.Count; $i++) {
    $reason = Test-PrimaryRouteValue -Value ([string]$routes[$i].normalized_route)
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Add-Violation -Artifact 'ROUTES_SUMMARY.json' -Field ("routes[{0}].normalized_route" -f $i) -Value ([string]$routes[$i].normalized_route) -Reason $reason
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'ROUTE_CONTRACT_BREACH'
    $violations | ConvertTo-Json -Depth 10 | Write-Host
    exit 1
}

Write-Host 'ROUTE_CONTRACT_OK'
exit 0
