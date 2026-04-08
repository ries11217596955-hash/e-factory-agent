Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = $env:GITHUB_WORKSPACE
if (-not [string]::IsNullOrWhiteSpace($workspace)) {
    $base = Join-Path $workspace 'agents/gh_batch/site_auditor_cloud'
}
else {
    $base = $PSScriptRoot
}

$outboxDir = Join-Path $base 'outbox'
$reportsDir = Join-Path $base 'reports'
$runtimeDir = Join-Path $base 'runtime'
$bundleRoot = Join-Path $base 'audit_bundle'
$bundleReport = Join-Path $bundleRoot 'REPORT.txt'
$masterSummaryPath = Join-Path $bundleRoot 'master_summary.json'
$inputInbox = Join-Path $base 'input/inbox'
$targetRepoPath = if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH)) { Join-Path $workspace 'target_repo' } else { $env:TARGET_REPO_PATH }
$timestamp = (Get-Date).ToString('o')

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Reset-Dir([string]$Path) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Write-JsonFile([string]$Path, [object]$Data) {
    $Data | ConvertTo-Json -Depth 20 | Out-File -FilePath $Path -Encoding utf8
}

function Resolve-Url {
    param(
        [string]$ExplicitUrl,
        [string]$DefaultUrl,
        [string]$RepoDiscovered,
        [string]$ZipDiscovered
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) {
        return @{ url = $ExplicitUrl.Trim(); source = 'explicit_input' }
    }
    if (-not [string]::IsNullOrWhiteSpace($DefaultUrl)) {
        return @{ url = $DefaultUrl.Trim(); source = 'default_env' }
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoDiscovered)) {
        return @{ url = $RepoDiscovered.Trim(); source = 'discovered_from_repo' }
    }
    if (-not [string]::IsNullOrWhiteSpace($ZipDiscovered)) {
        return @{ url = $ZipDiscovered.Trim(); source = 'discovered_from_zip' }
    }
    return @{ url = $null; source = 'none' }
}

function Discover-UrlFromRoot([string]$RootPath) {
    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path $RootPath -PathType Container)) {
        return $null
    }

    try {
        $raw = & (Join-Path $base 'lib/url_discovery.ps1') -Root $RootPath
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return [PSCustomObject]@{
            discovered_url = $null
            candidates = @()
            alternatives = @()
            scanned_files = @()
            warnings = @("URL discovery failed: $($_.Exception.Message)")
        }
    }
}

function Copy-ModeArtifacts {
    param([string]$ModeName)

    $modeOut = Join-Path $bundleRoot $ModeName
    Reset-Dir $modeOut

    $reportPath = Join-Path $outboxDir 'REPORT.txt'
    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    $manifestPath = Join-Path $reportsDir 'run_manifest.json'

    if (Test-Path $reportPath -PathType Leaf) { Copy-Item $reportPath (Join-Path $modeOut 'REPORT.txt') -Force }
    if (Test-Path $auditResultPath -PathType Leaf) { Copy-Item $auditResultPath (Join-Path $modeOut 'audit_result.json') -Force }
    if (Test-Path $manifestPath -PathType Leaf) { Copy-Item $manifestPath (Join-Path $modeOut 'run_manifest.json') -Force }

    $screenshotsSrc = Join-Path $reportsDir 'screenshots'
    if (Test-Path $screenshotsSrc -PathType Container) {
        Copy-Item $screenshotsSrc (Join-Path $modeOut 'screenshots') -Recurse -Force
    }
}

function Build-SkippedMode {
    param(
        [string]$ModeName,
        [string]$Reason,
        [string]$UrlSource,
        [string]$ResolvedUrl
    )

    $modeOut = Join-Path $bundleRoot $ModeName
    Reset-Dir $modeOut
    $when = (Get-Date).ToString('o')

    $audit = [ordered]@{
        status = 'SKIPPED'
        timestamp = $when
        mode = $ModeName.ToUpperInvariant()
        reason = $Reason
        source = @{ enabled = $false; required = $false; ok = $true; kind = $ModeName; summary = @{}; findings = @() }
        live = @{ enabled = $false; required = $false; ok = $true; base_url = $ResolvedUrl; summary = @{ page_quality_status = 'NOT_EVALUATED' }; findings = @('Live audit not evaluated for skipped mode.') }
        decision = @{ core_problem = $Reason; p0 = @(); p1 = @($Reason); p2 = @(); do_next = @('Provide required input to enable this mode.') }
        url_resolution = @{ resolved_url = $ResolvedUrl; provenance = $UrlSource }
    }
    $manifest = [ordered]@{
        mode = $ModeName.ToUpperInvariant()
        status = 'SKIPPED'
        timestamp = $when
        url_resolution = @{ resolved_url = $ResolvedUrl; provenance = $UrlSource }
        report_files = @("$ModeName/REPORT.txt", "$ModeName/audit_result.json", "$ModeName/run_manifest.json")
    }

    $report = @(
        "MODE: $($ModeName.ToUpperInvariant())",
        'OVERALL STATUS: SKIPPED',
        "REASON: $Reason",
        "URL SOURCE: $UrlSource",
        "BASE URL: $(if ($ResolvedUrl) { $ResolvedUrl } else { 'none' })"
    )

    $report -join "`n" | Out-File -FilePath (Join-Path $modeOut 'REPORT.txt') -Encoding utf8
    Write-JsonFile -Path (Join-Path $modeOut 'audit_result.json') -Data $audit
    Write-JsonFile -Path (Join-Path $modeOut 'run_manifest.json') -Data $manifest
}

function Invoke-Mode {
    param(
        [string]$ModeName,
        [string]$BaseUrl,
        [string]$UrlSource,
        [object]$Discovery
    )

    Reset-Dir $outboxDir
    Reset-Dir $reportsDir

    $env:BASE_URL = $BaseUrl
    $env:FORCE_MODE = $ModeName.ToUpperInvariant()
    & (Join-Path $base 'run.ps1') -MODE $ModeName.ToUpperInvariant()
    $exitCode = $LASTEXITCODE

    $auditPath = Join-Path $reportsDir 'audit_result.json'
    $manifestPath = Join-Path $reportsDir 'run_manifest.json'
    $reportPath = Join-Path $outboxDir 'REPORT.txt'

    $audit = Read-JsonFile $auditPath
    if ($null -eq $audit) {
        $audit = [ordered]@{
            status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
            mode = $ModeName.ToUpperInvariant()
            timestamp = (Get-Date).ToString('o')
            source = @{ enabled = $false; summary = @{} }
            live = @{ enabled = $false; summary = @{} }
            decision = @{ core_problem = 'Missing audit_result.json from mode run.'; p0 = @(); p1 = @('No audit_result.json emitted.'); p2 = @(); do_next = @() }
        }
    }

    $audit | Add-Member -NotePropertyName url_resolution -NotePropertyValue @{ resolved_url = $BaseUrl; provenance = $UrlSource } -Force
    if ($Discovery) {
        $audit | Add-Member -NotePropertyName url_discovery -NotePropertyValue $Discovery -Force
    }

    if ($audit.status -eq 'FAIL' -and $exitCode -eq 0) {
        $audit.status = 'PARTIAL'
    }

    Write-JsonFile -Path $auditPath -Data $audit

    $manifest = Read-JsonFile $manifestPath
    if ($null -eq $manifest) { $manifest = [ordered]@{ mode = $ModeName.ToUpperInvariant(); timestamp = (Get-Date).ToString('o') } }
    $manifest | Add-Member -NotePropertyName bundle_mode -NotePropertyValue 'TRI_AUDIT_TEMP' -Force
    $manifest | Add-Member -NotePropertyName url_resolution -NotePropertyValue @{ resolved_url = $BaseUrl; provenance = $UrlSource } -Force
    if ($Discovery) {
        $manifest | Add-Member -NotePropertyName url_discovery -NotePropertyValue $Discovery -Force
    }
    Write-JsonFile -Path $manifestPath -Data $manifest

    if (Test-Path $reportPath -PathType Leaf) {
        Add-Content -Path $reportPath -Value "URL SOURCE: $UrlSource"
        Add-Content -Path $reportPath -Value "BASE URL: $(if ($BaseUrl) { $BaseUrl } else { 'none' })"
    }

    Copy-ModeArtifacts -ModeName $ModeName.ToLowerInvariant()
    return [PSCustomObject]@{ mode = $ModeName.ToUpperInvariant(); status = [string]$audit.status; url_source = $UrlSource; base_url = $BaseUrl }
}

function Get-OverallStatus([object[]]$Modes) {
    $statuses = @($Modes | ForEach-Object { $_.status })
    $applicable = @($statuses | Where-Object { $_ -ne 'SKIPPED' })

    if ($applicable.Count -eq 0) { return 'SKIPPED' }
    if (@($applicable | Where-Object { $_ -eq 'PASS' }).Count -gt 0 -and @($applicable | Where-Object { $_ -eq 'FAIL' }).Count -eq 0) {
        if (@($applicable | Where-Object { $_ -eq 'PARTIAL' }).Count -gt 0) { return 'PARTIAL' }
        return 'PASS'
    }
    if (@($applicable | Where-Object { $_ -eq 'PASS' -or $_ -eq 'PARTIAL' }).Count -gt 0) { return 'PARTIAL' }
    return 'FAIL'
}

Reset-Dir $bundleRoot
Ensure-Dir (Join-Path $bundleRoot 'repo')
Ensure-Dir (Join-Path $bundleRoot 'zip')
Ensure-Dir (Join-Path $bundleRoot 'url')

$explicitInputUrl = $env:EXPLICIT_BASE_URL
$defaultUrl = $env:DEFAULT_BASE_URL
if ([string]::IsNullOrWhiteSpace($defaultUrl)) { $defaultUrl = $env:BASE_URL }

$repoDiscovery = $null
if (Test-Path $targetRepoPath -PathType Container) {
    $repoDiscovery = Discover-UrlFromRoot -RootPath $targetRepoPath
}

$zipPath = & (Join-Path $base 'lib/intake_zip.ps1') -InboxPath $inputInbox
$zipExtractRoot = Join-Path $runtimeDir 'bundle_zip_discovery'
$zipDiscovery = $null
if (-not [string]::IsNullOrWhiteSpace($zipPath) -and (Test-Path $zipPath -PathType Leaf)) {
    Reset-Dir $zipExtractRoot
    Expand-Archive -Path $zipPath -DestinationPath $zipExtractRoot -Force
    $zipDiscovery = Discover-UrlFromRoot -RootPath $zipExtractRoot
}

$repoResolved = Resolve-Url -ExplicitUrl $explicitInputUrl -DefaultUrl $defaultUrl -RepoDiscovered ($repoDiscovery.discovered_url) -ZipDiscovered $null
$zipResolved = Resolve-Url -ExplicitUrl $explicitInputUrl -DefaultUrl $defaultUrl -RepoDiscovered $null -ZipDiscovered ($zipDiscovery.discovered_url)
$urlResolved = Resolve-Url -ExplicitUrl $explicitInputUrl -DefaultUrl $defaultUrl -RepoDiscovered ($repoDiscovery.discovered_url) -ZipDiscovered ($zipDiscovery.discovered_url)

$modeResults = New-Object System.Collections.Generic.List[object]

if (Test-Path $targetRepoPath -PathType Container) {
    $modeResults.Add((Invoke-Mode -ModeName 'REPO' -BaseUrl $repoResolved.url -UrlSource $repoResolved.source -Discovery $repoDiscovery))
}
else {
    Build-SkippedMode -ModeName 'repo' -Reason 'TARGET_REPO_PATH not available; repo subrun skipped.' -UrlSource $repoResolved.source -ResolvedUrl $repoResolved.url
    $modeResults.Add([PSCustomObject]@{ mode = 'REPO'; status = 'SKIPPED'; url_source = $repoResolved.source; base_url = $repoResolved.url })
}

if (-not [string]::IsNullOrWhiteSpace($zipPath) -and (Test-Path $zipPath -PathType Leaf)) {
    $modeResults.Add((Invoke-Mode -ModeName 'ZIP' -BaseUrl $zipResolved.url -UrlSource $zipResolved.source -Discovery $zipDiscovery))
}
else {
    Build-SkippedMode -ModeName 'zip' -Reason 'No ZIP payload found in input/inbox; zip subrun skipped.' -UrlSource $zipResolved.source -ResolvedUrl $zipResolved.url
    $modeResults.Add([PSCustomObject]@{ mode = 'ZIP'; status = 'SKIPPED'; url_source = $zipResolved.source; base_url = $zipResolved.url })
}

if (-not [string]::IsNullOrWhiteSpace($urlResolved.url)) {
    $modeResults.Add((Invoke-Mode -ModeName 'URL' -BaseUrl $urlResolved.url -UrlSource $urlResolved.source -Discovery $null))
}
else {
    Build-SkippedMode -ModeName 'url' -Reason 'No explicit/default/discovered URL available; url subrun skipped.' -UrlSource 'none' -ResolvedUrl $null
    $modeResults.Add([PSCustomObject]@{ mode = 'URL'; status = 'SKIPPED'; url_source = 'none'; base_url = $null })
}

$overall = Get-OverallStatus -Modes @($modeResults)
$summaryLines = @(
    'SITE_AUDITOR TRI-AUDIT TEMP BUNDLE',
    "Generated: $timestamp",
    "REPO status: $((@($modeResults | Where-Object { $_.mode -eq 'REPO' })[0]).status)",
    "ZIP status: $((@($modeResults | Where-Object { $_.mode -eq 'ZIP' })[0]).status)",
    "URL status: $((@($modeResults | Where-Object { $_.mode -eq 'URL' })[0]).status)",
    "OVERALL status: $overall",
    '',
    'URL provenance:',
    "- repo: $($repoResolved.source)",
    "- zip: $($zipResolved.source)",
    "- url: $($urlResolved.source)"
)
$summaryLines -join "`n" | Out-File -FilePath $bundleReport -Encoding utf8

$masterSummary = [ordered]@{
    bundle_mode = 'TRI_AUDIT_TEMP'
    generated_at = $timestamp
    overall_status = $overall
    modes = @($modeResults)
    url_resolution = @{
        repo = $repoResolved
        zip = $zipResolved
        url = $urlResolved
    }
    discoveries = @{
        repo = $repoDiscovery
        zip = $zipDiscovery
    }
}
Write-JsonFile -Path $masterSummaryPath -Data $masterSummary

if ($overall -eq 'FAIL') {
    Write-Host 'TRI-AUDIT bundle completed with FAIL status.'
    exit 1
}

Write-Host "TRI-AUDIT bundle completed with $overall status."
exit 0
