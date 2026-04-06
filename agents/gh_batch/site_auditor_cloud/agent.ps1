param(
    [string]$Mode = 'REPO',
    [string]$TargetPath,
    [string]$BaseUrl = ''
)

$ErrorActionPreference = 'Stop'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 20
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

function Get-RouteMap() {
    return @(
        @{ path='/';            rel='src/index.md' },
        @{ path='/hubs/';       rel='src/hubs/index.njk' },
        @{ path='/tools/';      rel='src/tools/index.md' },
        @{ path='/start-here/'; rel='src/start-here/index.md' },
        @{ path='/search/';     rel='src/search/index.md' }
    )
}

function New-RepoRouteRecord([string]$RoutePath, [string]$RelPath, [string]$FilePath) {
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
        source = 'repo'
    }
}

function Get-RepoInventory([string]$RepoRoot) {
    $items = @()
    foreach ($entry in (Get-RouteMap)) {
        $filePath = Join-Path $RepoRoot $entry.rel
        $items += New-RepoRouteRecord -RoutePath $entry.path -RelPath $entry.rel -FilePath $filePath
    }
    return $items
}

function Get-RepoScores($Inventory) {
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

function Get-UrlInventory([string]$ManifestPath) {
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
    $raw = Get-Content -LiteralPath $ManifestPath -Raw
    $items = $raw | ConvertFrom-Json
    if ($null -eq $items) { throw 'visual_manifest.json is empty' }

    $out = @()
    foreach ($i in @($items)) {
        $status = 0
        try { $status = [int]$i.status } catch { $status = 0 }

        $band = 'ok'
        if ($status -lt 200 -or $status -ge 400) { $band = 'missing' }
        elseif ([int]$i.bodyTextLength -lt 220) { $band = 'bad' }
        elseif ([int]$i.bodyTextLength -lt 700) { $band = 'thin' }
        elseif ([int]$i.links -lt 2) { $band = 'weak' }

        $out += [pscustomobject]@{
            path = [string]$i.route_path
            file = [string]$i.url
            weight = (Get-Weight ([string]$i.route_path))
            band = $band
            exists = ($status -ge 200 -and $status -lt 400)
            len = [int]$i.bodyTextLength
            links = [int]$i.links
            images = [int]$i.images
            source = 'url'
            status = $status
            screenshotCount = [int]$i.screenshotCount
            title = [string]$i.title
        }
    }
    return $out
}

function Decide($Scores, [string]$Mode, [string]$TargetLabel) {
    $criticalBad = @($Scores | Where-Object { $_.weight -eq 'critical' -and $_.band -ne 'ok' })
    $highBad = @($Scores | Where-Object { $_.weight -eq 'high' -and $_.band -ne 'ok' })
    $missing = @($Scores | Where-Object { $_.band -eq 'missing' })

    $core = if ($missing.Count -gt 0) {
        if ($Mode -eq 'URL') { 'Some critical routes do not render correctly on the live site.' }
        else { 'Some required repo routes are missing or too weak.' }
    }
    elseif ($criticalBad.Count -gt 0) {
        if ($Mode -eq 'URL') { 'Critical live routes render, but look thin or weak.' }
        else { 'Core routes are present but thin or weak in the repo.' }
    }
    else {
        if ($Mode -eq 'URL') { 'Live site baseline is reachable on the checked routes.' }
        else { 'Repo baseline is present on the checked routes.' }
    }

    $p0 = @()
    if ($missing.Count -gt 0) { $p0 += ('Missing/broken required routes: ' + (($missing.path) -join ', ')) }
    if ($criticalBad.Count -gt 0) { $p0 += ('Weak critical routes: ' + (($criticalBad.path) -join ', ')) }

    $p1 = @()
    if ($highBad.Count -gt 0) { $p1 += ('High-value routes need more depth: ' + (($highBad.path) -join ', ')) }

    $next = @()
    if ($missing.Count -gt 0) { $next += 'Fix missing/broken required routes first.' }
    if ($criticalBad.Count -gt 0) { $next += 'Strengthen critical routes with real content and usable links.' }
    if ($highBad.Count -gt 0) { $next += 'Improve tools/start-here as guided entry pages.' }
    if ($next.Count -eq 0) { $next += 'Keep the current baseline stable.' }

    return [pscustomobject]@{
        target = $TargetLabel
        core = $core
        p0 = @($p0 | Select-Object -First 3)
        p1 = @($p1 | Select-Object -First 3)
        do = @($next | Select-Object -First 3)
    }
}

function Get-DoLines($Decision) {
    if ($null -eq $Decision.do -or @($Decision.do).Count -eq 0) {
        return '1. none'
    }
    $lines = @()
    for ($i = 0; $i -lt @($Decision.do).Count; $i++) {
        $lines += ('{0}. {1}' -f ($i + 1), $Decision.do[$i])
    }
    return ($lines -join "`n")
}

function Write-Report([string]$Path, $Decision, $Scores, [string]$Mode, [string]$TargetLabel, [bool]$LiveCaptureUsed) {
    $missingCount = @($Scores | Where-Object { $_.band -eq 'missing' }).Count
    $thinCount = @($Scores | Where-Object { $_.band -in @('bad','thin') }).Count
    $weakCount = @($Scores | Where-Object { $_.band -eq 'weak' }).Count
    $p0Lines = if (@($Decision.p0).Count -gt 0) { ((@($Decision.p0) | ForEach-Object { "- $_" }) -join "`n") } else { '- none' }
    $p1Lines = if (@($Decision.p1).Count -gt 0) { ((@($Decision.p1) | ForEach-Object { "- $_" }) -join "`n") } else { '- none' }
    $doLines = Get-DoLines $Decision

    @"
STATUS:
PASS

MODE:
$Mode

AUDIT SOURCE:
$(if ($Mode -eq 'URL') { 'LIVE / visual capture' } else { 'REPO / file truth' })

TARGET:
$TargetLabel

CORE PROBLEM:
$($Decision.core)

P0:
$p0Lines

P1:
$p1Lines

SUMMARY:
- Routes checked: $(@($Scores).Count)
- Missing/broken routes: $missingCount
- Empty/thin routes: $thinCount
- Weak routes: $weakCount
- Live capture used: $LiveCaptureUsed

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

switch ($resolvedMode) {
    'REPO' {
        $repoRoot = Get-RepoRoot $TargetPath
        $inventory = Get-RepoInventory -RepoRoot $repoRoot
        if (@($inventory).Count -eq 0) { throw 'No route inventory produced' }

        $routeScores = Get-RepoScores $inventory
        $decision = Decide -Scores $routeScores -Mode 'REPO' -TargetLabel $repoRoot

        $audit = [pscustomobject]@{
            status = 'PASS'
            mode = 'REPO'
            repo_bound = $true
            target = $repoRoot
            live_capture_used = $false
            routes = $routeScores
            decision = $decision
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile -Path (Join-Path $ReportsDir 'audit_result.json') -Object $audit
        Write-JsonFile -Path (Join-Path $ReportsDir 'HOW_TO_FIX.json') -Object ([pscustomobject]@{
            mode = 'REPO'
            target = $repoRoot
            steps = @($decision.do)
        })
        Write-Report -Path (Join-Path $ReportsDir 'REPORT.txt') -Decision $decision -Scores $routeScores -Mode 'REPO' -TargetLabel $repoRoot -LiveCaptureUsed $false
        "PASS REPO`n$repoRoot" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.ok') -Encoding UTF8
    }
    'URL' {
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) { throw 'BaseUrl is empty in URL mode' }
        $routeScores = Get-UrlInventory -ManifestPath $TargetPath
        if (@($routeScores).Count -eq 0) { throw 'No URL inventory produced' }

        $decision = Decide -Scores $routeScores -Mode 'URL' -TargetLabel $BaseUrl
        $manifestPath = $TargetPath
        $audit = [pscustomobject]@{
            status = 'PASS'
            mode = 'URL'
            repo_bound = $false
            target = $BaseUrl
            live_capture_used = $true
            manifest = $manifestPath
            routes = $routeScores
            decision = $decision
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile -Path (Join-Path $ReportsDir 'audit_result.json') -Object $audit
        Write-JsonFile -Path (Join-Path $ReportsDir 'HOW_TO_FIX.json') -Object ([pscustomobject]@{
            mode = 'URL'
            target = $BaseUrl
            steps = @($decision.do)
        })
        Write-Report -Path (Join-Path $ReportsDir 'REPORT.txt') -Decision $decision -Scores $routeScores -Mode 'URL' -TargetLabel $BaseUrl -LiveCaptureUsed $true
        "PASS URL`n$BaseUrl" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.ok') -Encoding UTF8
    }
    default {
        throw "Unsupported mode: $resolvedMode"
    }
}
