[CmdletBinding()]
param(
    [string]$FixturesRoot = 'tests/fixtures/site_auditor_v2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PrimaryRouteValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return 'empty' }
    $trimmed = ([string]$Value).Trim()
    if (-not $trimmed.StartsWith('/')) { return 'must_start_with_slash' }
    if ($trimmed -match '^[a-z][a-z0-9+\-.]*://') { return 'contains_scheme' }
    if ($trimmed -match '#') { return 'contains_fragment' }
    if (($trimmed.Length -gt 1) -and $trimmed.EndsWith('/')) { return 'trailing_slash_not_normalized' }
    return ''
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing required fixture artifact: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Empty JSON fixture artifact: $Path"
    }
    return $raw | ConvertFrom-Json -Depth 100
}

function Test-ArtifactPayload {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    $trimmed = $raw.Trim()
    if ($trimmed -in @('{}', '[]')) { return $false }
    if ($trimmed -match '(?i)\b(placeholder|todo|tbd|fake)\b') { return $false }
    $parsed = $trimmed | ConvertFrom-Json -Depth 100
    if ($parsed -is [System.Array] -and @($parsed).Count -eq 0) { return $false }
    if ($parsed -is [PSCustomObject] -and @($parsed.PSObject.Properties).Count -eq 0) { return $false }
    return $true
}

$fixtureDirs = Get-ChildItem -LiteralPath $FixturesRoot -Directory | Sort-Object Name
if ($fixtureDirs.Count -eq 0) {
    throw "No fixtures found in $FixturesRoot"
}

foreach ($fixtureDir in $fixtureDirs) {
    $runReportPath = Join-Path $fixtureDir.FullName 'RUN_REPORT.json'
    $routesSummaryPath = Join-Path $fixtureDir.FullName 'ROUTES_SUMMARY.json'
    $linkSummaryPath = Join-Path $fixtureDir.FullName 'LINK_SUMMARY.json'
    $actionSummaryPath = Join-Path $fixtureDir.FullName 'ACTION_SUMMARY.json'
    $visualManifestPath = Join-Path $fixtureDir.FullName 'visual_manifest.json'

    $runReport = Read-JsonFile -Path $runReportPath
    $routesSummary = Read-JsonFile -Path $routesSummaryPath
    $expected = Read-JsonFile -Path (Join-Path $fixtureDir.FullName 'expected.json')

    foreach ($artifactPath in @($runReportPath, $routesSummaryPath, $linkSummaryPath, $actionSummaryPath, $visualManifestPath)) {
        $isValidArtifact = Test-ArtifactPayload -Path $artifactPath
        if ($fixtureDir.Name -eq 'artifact_breach' -and $artifactPath -eq $actionSummaryPath) {
            if ($isValidArtifact) {
                throw "artifact_breach fixture requires invalid ACTION_SUMMARY.json."
            }
            continue
        }

        if (-not $isValidArtifact) {
            throw "Artifact contract failed for fixture '$($fixtureDir.Name)': $artifactPath"
        }
    }

    foreach ($record in @($runReport.selected_routes)) {
        $reason = Test-PrimaryRouteValue -Value ([string]$record.route)
        if (-not [string]::IsNullOrWhiteSpace($reason) -and $fixtureDir.Name -ne 'route_breach') {
            throw "Unexpected route breach in fixture '$($fixtureDir.Name)': $reason"
        }
    }
    foreach ($record in @($routesSummary.routes)) {
        $reason = Test-PrimaryRouteValue -Value ([string]$record.normalized_route)
        if (-not [string]::IsNullOrWhiteSpace($reason) -and $fixtureDir.Name -ne 'route_breach') {
            throw "Unexpected routes summary breach in fixture '$($fixtureDir.Name)': $reason"
        }
    }

    switch ([string]$fixtureDir.Name) {
        'happy_path' {
            if ($runReport.status -ne 'PASS') { throw 'happy_path must be PASS' }
            if ($runReport.route_contract.status -ne 'ok') { throw 'happy_path route contract must be ok' }
            if ($runReport.artifact_contract.status -ne 'ok') { throw 'happy_path artifact contract must be ok' }
        }
        'route_breach' {
            if ($runReport.status -ne 'FAIL') { throw 'route_breach must be FAIL' }
            if ($runReport.route_contract.status -ne 'failed') { throw 'route_breach route contract must be failed' }
            if (-not (@($runReport.failure_summary.reasons) -contains 'ROUTE_CONTRACT_BREACH')) { throw 'route_breach must include ROUTE_CONTRACT_BREACH reason' }
        }
        'artifact_breach' {
            if ($runReport.status -ne 'FAIL') { throw 'artifact_breach must be FAIL' }
            if ($runReport.artifact_contract.status -ne 'failed') { throw 'artifact_breach artifact contract must be failed' }
            if (-not (@($runReport.failure_summary.reasons) -contains 'ARTIFACT_CONTRACT_BREACH')) { throw 'artifact_breach must include ARTIFACT_CONTRACT_BREACH reason' }
        }
        'partial_run' {
            if ($runReport.status -ne 'PARTIAL') { throw 'partial_run must be PARTIAL' }
            if ($runReport.route_contract.status -ne 'ok') { throw 'partial_run route contract must be ok' }
            if ($runReport.artifact_contract.status -ne 'ok') { throw 'partial_run artifact contract must be ok' }
        }
        default {
            throw "Unexpected fixture folder: $($fixtureDir.Name)"
        }
    }

    if ([string]$expected.expect -eq '') {
        throw "Fixture '$($fixtureDir.Name)' missing expected outcome marker"
    }

    Write-Host "FIXTURE_OK: $($fixtureDir.Name)"
}

Write-Host 'ALL_FIXTURES_OK'
