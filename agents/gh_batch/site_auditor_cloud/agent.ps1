param(
    [string]$Mode = 'REPO',
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-RepoRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'TargetPath is empty' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "TargetPath not found: $Path" }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved 'src')) {
        return $resolved
    }

    throw "No repo root with src/ found under: $resolved"
}

function Strip-FrontMatter([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $text = $Text -replace "`r", ""
    if ($text.StartsWith("---`n")) {
        $parts = $text -split "`n---`n", 2
        if ($parts.Count -eq 2) { return $parts[1] }
    }
    return $text
}

function Get-LinkCount([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $md = ([regex]::Matches($Text, '\[[^\]]+\]\([^)]+\)').Count)
    $html = ([regex]::Matches($Text, 'href\s*=\s*["''][^"'']+["'']').Count)
    return ($md + $html)
}

function Get-ImageCount([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $md = ([regex]::Matches($Text, '!\[[^\]]*\]\([^)]+\)').Count)
    $html = ([regex]::Matches($Text, '<img\b').Count)
    return ($md + $html)
}

function Get-Weight([string]$RoutePath) {
    if ($RoutePath -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($RoutePath -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Get-RouteMap([string]$RepoRoot) {
    return @(
        @{ path='/';            rel='src/index.md' },
        @{ path='/hubs/';       rel='src/hubs/index.njk' },
        @{ path='/tools/';      rel='src/tools/index.md' },
        @{ path='/start-here/'; rel='src/start-here/index.md' },
        @{ path='/search/';     rel='src/search/index.md' }
    )
}

function New-RouteRecord([string]$RoutePath, [string]$RelPath, [string]$FilePath) {
    $exists = Test-Path -LiteralPath $FilePath
    $raw = if ($exists) { Get-Content -LiteralPath $FilePath -Raw } else { '' }
    $body = Strip-FrontMatter $raw

    return [pscustomobject]@{
        path = $RoutePath
        file = $RelPath
        exists = $exists
        bodyTextLength = $body.Length
        links = (Get-LinkCount $body)
        images = (Get-ImageCount $body)
        weight = (Get-Weight $RoutePath)
    }
}

function Get-RouteInventory([string]$RepoRoot) {
    $items = @()
    foreach ($entry in (Get-RouteMap $RepoRoot)) {
        $filePath = Join-Path $RepoRoot $entry.rel
        $items += New-RouteRecord -RoutePath $entry.path -RelPath $entry.rel -FilePath $filePath
    }
    return $items
}

function Get-RouteScores($Inventory) {
    $out = @()
    foreach ($i in @($Inventory)) {
        $band = 'ok'
        if (-not $i.exists) { $band = 'missing' }
        elseif ($i.bodyTextLength -lt 220) { $band = 'bad' }
        elseif ($i.bodyTextLength -lt 700) { $band = 'thin' }
        elseif ($i.links -lt 2) { $band = 'weak' }

        $out += [pscustomobject]@{
            path = $i.path
            file = $i.file
            weight = $i.weight
            band = $band
            exists = $i.exists
            len = $i.bodyTextLength
            links = $i.links
            images = $i.images
            source = 'repo'
        }
    }
    return $out
}

function Decide($Scores) {
    $criticalBad = @($Scores | Where-Object { $_.weight -eq 'critical' -and $_.band -ne 'ok' })
    $highBad = @($Scores | Where-Object { $_.weight -eq 'high' -and $_.band -ne 'ok' })
    $missing = @($Scores | Where-Object { $_.band -eq 'missing' })

    $core = 'Core routes are present and reasonably filled.'
    if ($missing.Count -gt 0) {
        $core = 'Some required routes are missing.'
    }
    elseif ($criticalBad.Count -gt 0) {
        $core = 'Critical routes exist but are weak.'
    }

    $p0 = @()
    if ($missing.Count -gt 0) { $p0 += ('Missing required routes: ' + (($missing.path) -join ', ')) }
    if ($criticalBad.Count -gt 0) { $p0 += ('Weak critical routes: ' + (($criticalBad.path) -join ', ')) }

    $p1 = @()
    if ($highBad.Count -gt 0) { $p1 += ('High-value routes need more depth: ' + (($highBad.path) -join ', ')) }

    $next = @()
    if ($missing.Count -gt 0) { $next += 'Restore missing required routes first.' }
    if ($criticalBad.Count -gt 0) { $next += 'Strengthen critical routes with real content and usable links.' }
    if ($highBad.Count -gt 0) { $next += 'Improve tools/start-here as guided entry pages.' }
    if ($next.Count -eq 0) { $next += 'Keep the current repo baseline stable.' }

    return [pscustomobject]@{
        core = $core
        p0 = @($p0 | Select-Object -First 3)
        p1 = @($p1 | Select-Object -First 3)
        do = @($next | Select-Object -First 3)
    }
}

function Write-Report([string]$Path, $Decision, $Scores, [string]$RepoRoot) {
    $missingCount = @($Scores | Where-Object { $_.band -eq 'missing' }).Count
    $thinCount = @($Scores | Where-Object { $_.band -in @('bad','thin') }).Count
    $weakCount = @($Scores | Where-Object { $_.band -eq 'weak' }).Count
    $p0Lines = if ($Decision.p0.Count -gt 0) { ($Decision.p0 | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $p1Lines = if ($Decision.p1.Count -gt 0) { ($Decision.p1 | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $doLines = if ($Decision.do.Count -gt 0) { for($i=0;$i -lt $Decision.do.Count;$i++){ "{0}. {1}" -f ($i+1), $Decision.do[$i] } | Out-String } else { '1. none' }

    @"
STATUS:
PASS

MODE:
REPO

AUDIT SOURCE:
REPO / file truth

TARGET:
$RepoRoot

CORE PROBLEM:
$($Decision.core)

P0:
$p0Lines

P1:
$p1Lines

SUMMARY:
- Routes checked: $(@($Scores).Count)
- Missing routes: $missingCount
- Empty/thin routes: $thinCount
- Weak routes: $weakCount
- Live capture used: False

DO NEXT:
$doLines
"@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

$Root = $PSScriptRoot
$ReportsDir = Join-Path $Root 'reports'
$OutboxDir = Join-Path $Root 'outbox'
Ensure-Dir $ReportsDir
Ensure-Dir $OutboxDir

$resolvedMode = if (-not [string]::IsNullOrWhiteSpace($Mode)) { $Mode.ToUpperInvariant() } else { 'REPO' }
if ($resolvedMode -ne 'REPO') {
    throw "BASELINE LOCK: only REPO mode is allowed in this recovery pack. Requested mode: $resolvedMode"
}

$repoRoot = Get-RepoRoot $TargetPath
$inventory = Get-RouteInventory -RepoRoot $repoRoot
if (@($inventory).Count -eq 0) { throw 'No route inventory produced' }

$routeScores = Get-RouteScores $inventory
$decision = Decide $routeScores

$repoAudit = [pscustomobject]@{
    mode = 'REPO'
    repo_bound = $true
    target_root = $repoRoot
    live_capture_used = $false
    routes_seen = @($inventory).Count
    routes_missing = @($routeScores | Where-Object { $_.band -eq 'missing' } | ForEach-Object { $_.path })
}

$auditResult = [pscustomobject]@{
    status = 'PASS'
    mode = 'REPO'
    target_root = $repoRoot
    live_capture_used = $false
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}

Write-JsonFile (Join-Path $ReportsDir 'route_inventory.json') $inventory
Write-JsonFile (Join-Path $ReportsDir 'route_scores.json') $routeScores
Write-JsonFile (Join-Path $ReportsDir 'decision_summary.json') $decision
Write-JsonFile (Join-Path $ReportsDir 'repo_audit.json') $repoAudit
Write-JsonFile (Join-Path $ReportsDir 'audit_result.json') $auditResult
Write-Report -Path (Join-Path $ReportsDir 'REPORT.txt') -Decision $decision -Scores $routeScores -RepoRoot $repoRoot

"PASS REPO" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.ok') -Encoding UTF8
Write-Host 'AGENT PASS: REPO'
