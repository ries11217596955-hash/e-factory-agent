\
param(
    [string]$Mode = "URL",
    [string]$TargetPath,
    [string]$BaseUrl
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function To-Int($Value) {
    try { return [int]$Value } catch { return 0 }
}

function Get-Weight([string]$Path) {
    if ($Path -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($Path -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Get-RepoRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'TargetPath is empty' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "TargetPath not found: $Path" }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $candidates = @(
        $resolved,
        (Join-Path $resolved 'src')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            $src = if ((Split-Path -Leaf $candidate) -eq 'src') { $candidate } else { Join-Path $candidate 'src' }
            if (Test-Path -LiteralPath $src) { return $resolved }
        }
    }

    $dirs = Get-ChildItem -LiteralPath $resolved -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        $src = Join-Path $dir.FullName 'src'
        if (Test-Path -LiteralPath $src) { return $dir.FullName }
    }

    throw "No site repo root with src/ found under: $resolved"
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
    $count = 0
    $count += ([regex]::Matches($Text, '\[[^\]]+\]\([^)]+\)').Count)
    $count += ([regex]::Matches($Text, 'href\s*=\s*["''][^"'']+["'']').Count)
    return $count
}

function Get-ImageCount([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $count = 0
    $count += ([regex]::Matches($Text, '!\[[^\]]*\]\([^)]+\)').Count)
    $count += ([regex]::Matches($Text, '<img\b').Count)
    return $count
}

function Get-TitleFromPath([string]$FilePath) {
    return [System.IO.Path]::GetFileName($FilePath)
}

function New-RouteRecord([string]$RoutePath, [string]$Source, [string]$RelPath, [string]$FilePath) {
    $exists = Test-Path -LiteralPath $FilePath
    $raw = if ($exists) { Get-Content -LiteralPath $FilePath -Raw } else { '' }
    $body = Strip-FrontMatter $raw
    return [pscustomobject]@{
        path = $RoutePath
        source = $Source
        file = $RelPath
        exists = $exists
        title = (Get-TitleFromPath $FilePath)
        bodyTextLength = ($body.Length)
        links = (Get-LinkCount $body)
        images = (Get-ImageCount $body)
        screenshotCount = 0
        contentMetricsPresent = ($body.Length -gt 0)
        weight = (Get-Weight $RoutePath)
    }
}

function Get-RouteInventoryFromRepo([string]$RepoRoot, [string]$Source) {
    $items = @()
    foreach ($entry in (Get-RouteMap $RepoRoot)) {
        $filePath = Join-Path $RepoRoot $entry.rel
        $items += New-RouteRecord -RoutePath $entry.path -Source $Source -RelPath $entry.rel -FilePath $filePath
    }
    return $items
}

function Get-VisualManifest([string]$RootDir) {
    $manifestPath = Join-Path $RootDir 'reports/visual_manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return @() }
    try {
        $json = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return @($json)
    } catch {
        return @()
    }
}

function Get-RouteInventoryFromVisual($ManifestItems) {
    $items = @()
    foreach ($i in @($ManifestItems)) {
        $routePath = '/'
        if ($null -ne $i.url -and -not [string]::IsNullOrWhiteSpace([string]$i.url)) {
            try {
                $routePath = ([uri]([string]$i.url)).AbsolutePath
                if ([string]::IsNullOrWhiteSpace($routePath)) { $routePath = '/' }
            } catch {
                $routePath = '/'
            }
        }
        $items += [pscustomobject]@{
            path = $routePath
            source = 'url'
            file = $null
            exists = $true
            title = [string]$i.title
            bodyTextLength = (To-Int $i.bodyTextLength)
            links = (To-Int $i.links)
            images = (To-Int $i.images)
            screenshotCount = (To-Int $i.screenshotCount)
            contentMetricsPresent = [bool]$i.contentMetricsPresent
            weight = (Get-Weight $routePath)
        }
    }
    return $items
}

function Get-VisualFindings($Inventory) {
    $out = @()
    foreach ($i in @($Inventory)) {
        $visual = 'ok'
        if (-not $i.exists) { $visual = 'missing' }
        elseif ($i.bodyTextLength -lt 220) { $visual = 'empty' }
        elseif ($i.bodyTextLength -lt 700) { $visual = 'thin' }
        elseif ($i.links -lt 2) { $visual = 'weak' }
        $out += [pscustomobject]@{
            path = $i.path
            visual = $visual
            len = $i.bodyTextLength
            links = $i.links
            img = $i.images
            exists = $i.exists
            screenshotCount = $i.screenshotCount
            source = $i.source
        }
    }
    return $out
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
            weight = $i.weight
            band = $band
            len = $i.bodyTextLength
            links = $i.links
            exists = $i.exists
            source = $i.source
        }
    }
    return $out
}

function Get-PageTypeAudit($Inventory) {
    $out = @()
    foreach ($i in @($Inventory)) {
        $state = 'OK'
        if (-not $i.exists) { $state = 'MISSING' }
        elseif ($i.bodyTextLength -lt 220) { $state = 'EMPTY' }
        elseif ($i.bodyTextLength -lt 700) { $state = 'THIN' }
        elseif ($i.links -lt 2) { $state = 'WEAK' }
        $out += [pscustomobject]@{
            path = $i.path
            state = $state
            text_length = $i.bodyTextLength
            links = $i.links
            exists = $i.exists
            source = $i.source
        }
    }
    return $out
}

function Analyze-System($Scores) {
    $router = $false
    $flow = $false
    foreach ($s in @($Scores)) {
        if ($s.path -eq '/hubs/' -and $s.exists) { $router = $true }
        if ($s.path -eq '/search/' -and $s.exists) { $flow = $true }
    }
    return [pscustomobject]@{
        router = $router
        flow = $flow
    }
}

function Decide($Scores) {
    $sys = Analyze-System $Scores
    $criticalBad = @($Scores | Where-Object { $_.weight -eq 'critical' -and $_.band -ne 'ok' })
    $highBad = @($Scores | Where-Object { $_.weight -eq 'high' -and $_.band -ne 'ok' })
    $missing = @($Scores | Where-Object { $_.band -eq 'missing' })

    $core = 'Critical routes exist but are weak.'
    if ($missing.Count -gt 0) {
        $core = 'Some required routes are missing.'
    } elseif (-not $sys.router -or -not $sys.flow) {
        $core = 'Site does not function as a decision system (missing router or search layer).'
    } elseif ($criticalBad.Count -eq 0 -and $highBad.Count -eq 0) {
        $core = 'Core routes are present and reasonably filled.'
    }

    $p0 = @()
    if (-not $sys.router) { $p0 += 'Router layer missing or broken: /hubs/' }
    if (-not $sys.flow) { $p0 += 'Search/discovery layer missing or broken: /search/' }
    if ($missing.Count -gt 0) { $p0 += ('Missing required routes: ' + (($missing.path) -join ', ')) }
    if ($criticalBad.Count -gt 0) { $p0 += ('Weak critical routes: ' + (($criticalBad.path) -join ', ')) }

    $p1 = @()
    if ($highBad.Count -gt 0) { $p1 += ('High-value routes need more depth: ' + (($highBad.path) -join ', ')) }

    $do = @()
    if ($missing.Count -gt 0) { $do += 'Restore missing required routes first.' }
    if ($criticalBad.Count -gt 0) { $do += 'Strengthen critical routes with real content and usable links.' }
    if ($highBad.Count -gt 0) { $do += 'Improve tools/start-here as guided entry pages.' }
    if ($do.Count -eq 0) { $do += 'Keep the current route baseline stable and expand carefully.' }

    return [pscustomobject]@{
        core = $core
        p0 = @($p0 | Select-Object -First 3)
        p1 = @($p1 | Select-Object -First 3)
        do = @($do | Select-Object -First 3)
    }
}

function Get-UnifiedCompare($FileScores, $LiveScores) {
    $map = @{}
    foreach ($s in @($FileScores)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$s.path)) {
            $map[[string]$s.path] = [ordered]@{ file = $s; live = $null }
        }
    }
    foreach ($s in @($LiveScores)) {
        $k = [string]$s.path
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        if (-not $map.ContainsKey($k)) { $map[$k] = [ordered]@{ file = $null; live = $s } }
        else { $map[$k].live = $s }
    }

    $rank = @{ missing = 4; bad = 3; thin = 2; weak = 1; ok = 0 }
    $out = @()
    foreach ($k in ($map.Keys | Sort-Object)) {
        $fileBand = if ($null -ne $map[$k].file) { [string]$map[$k].file.band } else { 'missing' }
        $liveBand = if ($null -ne $map[$k].live) { [string]$map[$k].live.band } else { 'missing' }
        $delta = $rank[$liveBand] - $rank[$fileBand]
        $status = 'same'
        if ($delta -gt 0) { $status = 'live_worse' }
        elseif ($delta -lt 0) { $status = 'live_better' }

        $out += [pscustomobject]@{
            path = $k
            file_band = $fileBand
            live_band = $liveBand
            delta = $delta
            status = $status
        }
    }
    return $out
}

function Write-JsonFile([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-StandardReport([string]$Path, [string]$Status, [string]$Mode, $Decision, $Scores, [bool]$LiveCaptureUsed, [string]$TargetRoot) {
    $missingCount = @($Scores | Where-Object { $_.band -eq 'missing' }).Count
    $thinCount = @($Scores | Where-Object { $_.band -in @('bad','thin') }).Count
    $weakCount = @($Scores | Where-Object { $_.band -eq 'weak' }).Count
    $p0Lines = if ($Decision.p0.Count -gt 0) { ($Decision.p0 | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $p1Lines = if ($Decision.p1.Count -gt 0) { ($Decision.p1 | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $doLines = if ($Decision.do.Count -gt 0) { ($Decision.do | ForEach-Object { "$([array]::IndexOf($Decision.do, $_)+1). $_" }) -join "`n" } else { '1. none' }
    $sourceLabel = switch ($Mode) {
        'REPO' { 'REPO / file truth' }
        'ZIP'  { 'ZIP / file truth' }
        'URL'  { 'URL / live truth' }
        default { $Mode }
    }

@"
STATUS:
$Status

MODE:
$Mode

AUDIT SOURCE:
$sourceLabel

TARGET:
$TargetRoot

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
- Live capture used: $LiveCaptureUsed

DO NEXT:
$doLines
"@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-UnifiedReport([string]$Path, [string]$Status, [string]$TargetRoot, [string]$BaseUrl, $FileDecision, $LiveDecision, $FileScores, $LiveScores, $Compare) {
    $fileMissing = @($FileScores | Where-Object { $_.band -eq 'missing' }).Count
    $fileThin = @($FileScores | Where-Object { $_.band -in @('bad','thin') }).Count
    $fileWeak = @($FileScores | Where-Object { $_.band -eq 'weak' }).Count
    $liveMissing = @($LiveScores | Where-Object { $_.band -eq 'missing' }).Count
    $liveThin = @($LiveScores | Where-Object { $_.band -in @('bad','thin') }).Count
    $liveWeak = @($LiveScores | Where-Object { $_.band -eq 'weak' }).Count

    $deltaBad = @($Compare | Where-Object { $_.status -eq 'live_worse' })
    $deltaGood = @($Compare | Where-Object { $_.status -eq 'live_better' })

    $deltaBlock = if ($deltaBad.Count -gt 0) {
        ($deltaBad | Select-Object -First 3 | ForEach-Object { "- $($_.path): file=$($_.file_band), live=$($_.live_band)" }) -join "`n"
    } else {
        '- no live-worse deltas on critical set'
    }

    $next = @()
    $next += 'Fix routes that are weak in both FILE and LIVE layers first.'
    if ($deltaBad.Count -gt 0) { $next += 'Investigate FILE→LIVE degradation on routes listed in DELTA.' }
    $next += 'Keep REPO checks and URL capture separate; compare them through unified report only.'
    $nextText = ($next | Select-Object -First 3 | ForEach-Object { "$([array]::IndexOf($next, $_)+1). $_" }) -join "`n"

@"
STATUS:
$Status

MODE:
UNIFIED

AUDIT SOURCE:
FILE + LIVE

TARGET REPO:
$TargetRoot

BASE URL:
$BaseUrl

FILE CORE:
$($FileDecision.core)

LIVE CORE:
$($LiveDecision.core)

FILE SUMMARY:
- Routes checked: $(@($FileScores).Count)
- Missing routes: $fileMissing
- Empty/thin routes: $fileThin
- Weak routes: $fileWeak

LIVE SUMMARY:
- Routes checked: $(@($LiveScores).Count)
- Missing routes: $liveMissing
- Empty/thin routes: $liveThin
- Weak routes: $liveWeak
- Live capture used: True

DELTA (LIVE vs FILE):
$deltaBlock

DO NEXT:
$nextText
"@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ReportsDir = Join-Path $Root 'reports'
$OutboxDir = Join-Path $Root 'outbox'
Ensure-Dir $ReportsDir
Ensure-Dir $OutboxDir

$resolvedMode = if (-not [string]::IsNullOrWhiteSpace($Mode)) { $Mode.ToUpperInvariant() } else { 'URL' }

switch ($resolvedMode) {
    'REPO' {
        $repoRoot = Get-RepoRoot $TargetPath
        $inventory = Get-RouteInventoryFromRepo -RepoRoot $repoRoot -Source 'repo'
        if (@($inventory).Count -eq 0) { throw "No inventory produced for mode $resolvedMode" }

        $visualFindings = Get-VisualFindings $inventory
        $routeScores = Get-RouteScores $inventory
        $pageTypeAudit = Get-PageTypeAudit $inventory
        $decision = Decide $routeScores
        $status = 'PASS'

        $repoAudit = [pscustomobject]@{
            mode = $resolvedMode
            repo_bound = $true
            target_root = $repoRoot
            live_capture_used = $false
            routes_seen = @($inventory).Count
            routes_missing = @($routeScores | Where-Object { $_.band -eq 'missing' } | ForEach-Object { $_.path })
        }

        $auditResult = [pscustomobject]@{
            status = $status
            mode = $resolvedMode
            target_root = $repoRoot
            live_capture_used = $false
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile (Join-Path $ReportsDir 'route_inventory.json') $inventory
        Write-JsonFile (Join-Path $ReportsDir 'visual_findings.json') $visualFindings
        Write-JsonFile (Join-Path $ReportsDir 'route_scores.json') $routeScores
        Write-JsonFile (Join-Path $ReportsDir 'page_type_audit.json') $pageTypeAudit
        Write-JsonFile (Join-Path $ReportsDir 'decision_summary.json') $decision
        Write-JsonFile (Join-Path $ReportsDir 'repo_audit.json') $repoAudit
        Write-JsonFile (Join-Path $ReportsDir 'audit_result.json') $auditResult
        Write-StandardReport -Path (Join-Path $ReportsDir 'REPORT.txt') -Status $status -Mode $resolvedMode -Decision $decision -Scores $routeScores -LiveCaptureUsed $false -TargetRoot $repoRoot
    }
    'ZIP' {
        $repoRoot = Get-RepoRoot $TargetPath
        $inventory = Get-RouteInventoryFromRepo -RepoRoot $repoRoot -Source 'zip'
        if (@($inventory).Count -eq 0) { throw "No inventory produced for mode $resolvedMode" }

        $visualFindings = Get-VisualFindings $inventory
        $routeScores = Get-RouteScores $inventory
        $pageTypeAudit = Get-PageTypeAudit $inventory
        $decision = Decide $routeScores
        $status = 'PASS'

        $repoAudit = [pscustomobject]@{
            mode = $resolvedMode
            repo_bound = $true
            target_root = $repoRoot
            live_capture_used = $false
            routes_seen = @($inventory).Count
            routes_missing = @($routeScores | Where-Object { $_.band -eq 'missing' } | ForEach-Object { $_.path })
        }

        $auditResult = [pscustomobject]@{
            status = $status
            mode = $resolvedMode
            target_root = $repoRoot
            live_capture_used = $false
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile (Join-Path $ReportsDir 'route_inventory.json') $inventory
        Write-JsonFile (Join-Path $ReportsDir 'visual_findings.json') $visualFindings
        Write-JsonFile (Join-Path $ReportsDir 'route_scores.json') $routeScores
        Write-JsonFile (Join-Path $ReportsDir 'page_type_audit.json') $pageTypeAudit
        Write-JsonFile (Join-Path $ReportsDir 'decision_summary.json') $decision
        Write-JsonFile (Join-Path $ReportsDir 'repo_audit.json') $repoAudit
        Write-JsonFile (Join-Path $ReportsDir 'audit_result.json') $auditResult
        Write-StandardReport -Path (Join-Path $ReportsDir 'REPORT.txt') -Status $status -Mode $resolvedMode -Decision $decision -Scores $routeScores -LiveCaptureUsed $false -TargetRoot $repoRoot
    }
    'URL' {
        if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) { $env:BASE_URL = $BaseUrl }
        & node (Join-Path $Root 'capture.mjs')
        if ($LASTEXITCODE -ne 0) { throw "capture.mjs failed with exit code $LASTEXITCODE" }

        $inventory = Get-RouteInventoryFromVisual (Get-VisualManifest $Root)
        if (@($inventory).Count -eq 0) { throw "No inventory produced for mode $resolvedMode" }

        $visualFindings = Get-VisualFindings $inventory
        $routeScores = Get-RouteScores $inventory
        $pageTypeAudit = Get-PageTypeAudit $inventory
        $decision = Decide $routeScores
        $status = 'PASS'
        $repoRoot = $env:BASE_URL

        $repoAudit = [pscustomobject]@{
            mode = $resolvedMode
            repo_bound = $false
            target_root = $repoRoot
            live_capture_used = $true
            routes_seen = @($inventory).Count
            routes_missing = @($routeScores | Where-Object { $_.band -eq 'missing' } | ForEach-Object { $_.path })
        }

        $auditResult = [pscustomobject]@{
            status = $status
            mode = $resolvedMode
            target_root = $repoRoot
            live_capture_used = $true
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile (Join-Path $ReportsDir 'route_inventory.json') $inventory
        Write-JsonFile (Join-Path $ReportsDir 'visual_findings.json') $visualFindings
        Write-JsonFile (Join-Path $ReportsDir 'route_scores.json') $routeScores
        Write-JsonFile (Join-Path $ReportsDir 'page_type_audit.json') $pageTypeAudit
        Write-JsonFile (Join-Path $ReportsDir 'decision_summary.json') $decision
        Write-JsonFile (Join-Path $ReportsDir 'repo_audit.json') $repoAudit
        Write-JsonFile (Join-Path $ReportsDir 'audit_result.json') $auditResult
        Write-StandardReport -Path (Join-Path $ReportsDir 'REPORT.txt') -Status $status -Mode $resolvedMode -Decision $decision -Scores $routeScores -LiveCaptureUsed $true -TargetRoot $repoRoot
    }
    'UNIFIED' {
        $repoRoot = Get-RepoRoot $TargetPath
        if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) { $env:BASE_URL = $BaseUrl }

        $fileInventory = Get-RouteInventoryFromRepo -RepoRoot $repoRoot -Source 'repo'
        & node (Join-Path $Root 'capture.mjs')
        if ($LASTEXITCODE -ne 0) { throw "capture.mjs failed with exit code $LASTEXITCODE" }
        $liveInventory = Get-RouteInventoryFromVisual (Get-VisualManifest $Root)

        if (@($fileInventory).Count -eq 0) { throw 'No FILE inventory produced for UNIFIED mode' }
        if (@($liveInventory).Count -eq 0) { throw 'No LIVE inventory produced for UNIFIED mode' }

        $fileScores = Get-RouteScores $fileInventory
        $liveScores = Get-RouteScores $liveInventory
        $compare = Get-UnifiedCompare -FileScores $fileScores -LiveScores $liveScores
        $fileDecision = Decide $fileScores
        $liveDecision = Decide $liveScores

        $status = 'PASS'
        $auditResult = [pscustomobject]@{
            status = $status
            mode = 'UNIFIED'
            target_root = $repoRoot
            base_url = $env:BASE_URL
            live_capture_used = $true
            checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        }

        Write-JsonFile (Join-Path $ReportsDir 'route_inventory_file.json') $fileInventory
        Write-JsonFile (Join-Path $ReportsDir 'route_inventory_live.json') $liveInventory
        Write-JsonFile (Join-Path $ReportsDir 'route_scores_file.json') $fileScores
        Write-JsonFile (Join-Path $ReportsDir 'route_scores_live.json') $liveScores
        Write-JsonFile (Join-Path $ReportsDir 'decision_summary_file.json') $fileDecision
        Write-JsonFile (Join-Path $ReportsDir 'decision_summary_live.json') $liveDecision
        Write-JsonFile (Join-Path $ReportsDir 'unified_compare.json') $compare
        Write-JsonFile (Join-Path $ReportsDir 'audit_result.json') $auditResult
        Write-UnifiedReport -Path (Join-Path $ReportsDir 'REPORT.txt') -Status $status -TargetRoot $repoRoot -BaseUrl $env:BASE_URL -FileDecision $fileDecision -LiveDecision $liveDecision -FileScores $fileScores -LiveScores $liveScores -Compare $compare
    }
    default {
        throw "Unsupported mode: $resolvedMode"
    }
}

"PASS $resolvedMode" | Set-Content -LiteralPath (Join-Path $OutboxDir 'DONE.ok') -Encoding UTF8
Write-Host "AGENT PASS: $resolvedMode"
