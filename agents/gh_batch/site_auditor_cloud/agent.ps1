param(
    [string]$Mode = 'REPO',
    [string]$TargetPath,
    [string]$BaseUrl = ''
)

$ErrorActionPreference = 'Stop'

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Normalize { param($x) return @($x) }

function Get-Weight {
    param([string]$p)
    if ($p -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($p -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Strip-FrontMatter {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace '(?s)^---\s*.*?\s*---\s*', '')
}

function Get-RouteFileMap {
    param([string]$RootPath)
    $map = [ordered]@{}
    $candidates = [ordered]@{
        '/' = @('src/index.md','src/index.njk','src/index.html')
        '/start-here/' = @('src/start-here/index.md','src/start-here/index.njk','src/start-here/index.html')
        '/tools/' = @('src/tools/index.md','src/tools/index.njk','src/tools/index.html')
        '/hubs/' = @('src/hubs/index.md','src/hubs/index.njk','src/hubs/index.html')
        '/search/' = @('src/search/index.md','src/search/index.njk','src/search/index.html')
    }
    foreach ($route in $candidates.Keys) {
        foreach ($rel in $candidates[$route]) {
            $full = Join-Path $RootPath $rel
            if (Test-Path -LiteralPath $full) {
                $map[$route] = $full
                break
            }
        }
    }
    return $map
}

function Get-TextMetrics {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return [pscustomobject]@{ text=''; len=0; links=0; images=0; title='' }
    }
    $raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $title = ''
    $m = [regex]::Match($raw, '(?im)^title\s*:\s*["'']?(.*?)["'']?\s*$')
    if ($m.Success) { $title = $m.Groups[1].Value.Trim() }
    $body = Strip-FrontMatter $raw
    $body = [regex]::Replace($body, '<[^>]+>', ' ')
    $body = [regex]::Replace($body, '!\[[^\]]*\]\([^\)]*\)', ' IMG ')
    $body = [regex]::Replace($body, '\[[^\]]+\]\([^\)]*\)', ' LINK ')
    $plain = [regex]::Replace($body, '\s+', ' ').Trim()
    $links = ([regex]::Matches($raw, '\[[^\]]+\]\([^\)]*\)').Count + [regex]::Matches($raw, '(?i)<a\b').Count)
    $images = ([regex]::Matches($raw, '!\[[^\]]*\]\([^\)]*\)').Count + [regex]::Matches($raw, '(?i)<img\b').Count)
    return [pscustomobject]@{
        text = $plain
        len = $plain.Length
        links = $links
        images = $images
        title = $title
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LiveManifestMap {
    param([string]$ManifestPath)
    $map = @{}
    $manifest = Read-JsonFile $ManifestPath
    foreach ($item in (Normalize $manifest)) {
        if ($null -eq $item) { continue }
        $p = '/'
        try {
            if ($item.route_path) { $p = [string]$item.route_path }
            elseif ($item.url) { $p = ([uri]$item.url).AbsolutePath }
        } catch {}
        $map[$p] = $item
    }
    return $map
}

function Get-RouteInventory {
    param([hashtable]$RouteMap, [hashtable]$LiveMap)
    $out = @()
    foreach ($route in $RouteMap.Keys) {
        $metrics = Get-TextMetrics -FilePath $RouteMap[$route]
        $live = $null
        if ($LiveMap.ContainsKey($route)) { $live = $LiveMap[$route] }
        $screenshotCount = 0
        if ($null -ne $live) {
            try { $screenshotCount = [int]$live.screenshotCount } catch { $screenshotCount = 0 }
        }
        $out += [pscustomobject]@{
            path = $route
            file = $RouteMap[$route]
            title = [string]$metrics.title
            bodyTextLength = [int]$metrics.len
            links = [int]$metrics.links
            images = [int]$metrics.images
            screenshotCount = $screenshotCount
            contentMetricsPresent = ($metrics.len -gt 0)
            weight = Get-Weight $route
        }
    }
    return $out
}

function Get-VisualFindings {
    param($items)
    $out = @()
    foreach ($i in (Normalize $items)) {
        $len = [int]$i.bodyTextLength
        $links = [int]$i.links
        $img = [int]$i.images
        $p = [string]$i.path
        $visual = 'ok'
        if ($len -lt 220) { $visual = 'empty' }
        elseif ($len -lt 700) { $visual = 'thin' }
        elseif ($links -lt 2) { $visual = 'weak' }
        $out += [pscustomobject]@{ path=$p; visual=$visual; len=$len; links=$links; img=$img }
    }
    return $out
}

function Get-RouteScores {
    param($items)
    $out = @()
    foreach ($i in (Normalize $items)) {
        $band='ok'
        $len=[int]$i.bodyTextLength
        $links=[int]$i.links
        if($len -lt 220){$band='bad'} elseif($len -lt 700){$band='thin'} elseif($links -lt 2){$band='weak'}
        $out += [pscustomobject]@{ path=[string]$i.path; weight=[string]$i.weight; band=$band; len=$len; links=$links }
    }
    return $out
}

function Get-PageTypeAudit {
    param($items)
    $out = @()
    foreach($i in (Normalize $items)){
        $len=[int]$i.bodyTextLength
        $links=[int]$i.links
        $state='OK'
        if($len -lt 220){$state='EMPTY'} elseif($len -lt 700){$state='THIN'} elseif($links -lt 2){$state='WEAK'}
        $out += [pscustomobject]@{ path=[string]$i.path; state=$state; text_length=$len; links=$links }
    }
    return $out
}

function Get-RepoAudit {
    param([string]$Mode, [string]$RootPath, $inventory)
    return [pscustomobject]@{
        mode = $Mode
        repo_bound = (Test-Path -LiteralPath $RootPath)
        target_root = $RootPath
        routes_seen = @($inventory).Count
        notes = @(
            ('Audit mode: ' + $Mode),
            ('Target root: ' + $RootPath)
        )
    }
}

function Analyze-System {
    param($scores, $inventory)
    $router = (@($inventory | Where-Object { $_.path -eq '/hubs/' })).Count -gt 0
    $flow   = (@($inventory | Where-Object { $_.path -eq '/search/' })).Count -gt 0
    $next   = (@($inventory | Where-Object { $_.bodyTextLength -gt 200 })).Count -gt 0
    return [pscustomobject]@{ router=$router; flow=$flow; next_step=$next }
}

function Decide {
    param($scores,$findings,$inventory)
    $sys=Analyze-System $scores $inventory
    $crit=@()
    foreach($s in $scores){ if($s.weight -eq 'critical' -and $s.band -ne 'ok'){ $crit += $s.path } }
    $core='Site exists but is not a functional system.'
    if(-not $sys.router -or -not $sys.flow){ $core='Site does not function as a decision system (no routing / flow).' }
    elseif($crit.Count -gt 0){ $core='Critical routes are shallow and break navigation.' }
    $p0=@(); $p1=@(); $do=@()
    if(-not $sys.router){ $p0 += 'No router layer (hubs missing)' }
    if(-not $sys.flow){ $p0 += 'No discovery flow (search missing)' }
    if($crit.Count -gt 0){ $p0 += 'Critical routes shallow: ' + ($crit -join ', ') }
    $thinHigh=@(); foreach($s in $scores){ if($s.weight -eq 'high' -and $s.band -ne 'ok'){ $thinHigh += $s.path } }
    if($thinHigh.Count -gt 0){ $p1 += 'High-value routes need more depth: ' + ($thinHigh -join ', ') }
    if($crit -contains '/hubs/'){ $do += 'Build hubs as router' }
    if($crit -contains '/search/' -or -not $sys.flow){ $do += 'Fix search as entry' }
    if($thinHigh.Count -gt 0){ $do += 'Strengthen tools/start-here as guided routes' }
    return [pscustomobject]@{ core=$core; p0=($p0|Select-Object -First 3); p1=($p1|Select-Object -First 3); do=($do|Select-Object -First 3) }
}

function Write-TextFile {
    param([string]$Path,[string[]]$Lines)
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value ($Lines -join [Environment]::NewLine)
}

function Write-Report {
    param($Decision,$Inventory,$Findings,[string]$OutPath,[string]$Mode,[string]$TargetRoot)
    $criticalCount = (@($Inventory | Where-Object { $_.weight -eq 'critical' })).Count
    $badCount = (@($Findings | Where-Object { $_.visual -in @('empty','thin') })).Count
    $lines = @(
        'SITE STAGE:',
        'Structure / routing baseline',
        '',
        'AUDIT MODE:',
        $Mode,
        '',
        'AUDIT ROOT:',
        $TargetRoot,
        '',
        'CORE PROBLEM:',
        [string]$Decision.core,
        '',
        'P0:'
    )
    if(@($Decision.p0).Count -eq 0){ $lines += '- none' } else { $Decision.p0 | ForEach-Object { $lines += '- ' + $_ } }
    $lines += ''
    $lines += 'P1:'
    if(@($Decision.p1).Count -eq 0){ $lines += '- none' } else { $Decision.p1 | ForEach-Object { $lines += '- ' + $_ } }
    $lines += ''
    $lines += 'VISUAL SUMMARY:'
    $lines += '- Routes checked: ' + @($Inventory).Count
    $lines += '- Critical routes: ' + $criticalCount
    $lines += '- Empty/thin routes: ' + $badCount
    $lines += ''
    $lines += 'DO NEXT:'
    if(@($Decision.do).Count -eq 0){ $lines += '1. Strengthen top routes' } else {
        $n=1; foreach($x in $Decision.do){ $lines += ($n.ToString() + '. ' + $x); $n++ }
    }
    Write-TextFile -Path $OutPath -Lines $lines
}

$root = Get-ScriptRoot
$reports = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
if ([string]::IsNullOrWhiteSpace($TargetPath)) { throw 'TargetPath is required' }
if (-not (Test-Path -LiteralPath $TargetPath)) { throw "TargetPath not found: $TargetPath" }
$routeMap = Get-RouteFileMap -RootPath $TargetPath
if ($routeMap.Count -eq 0) { throw "No known site routes found under: $TargetPath" }
$liveMap = Get-LiveManifestMap -ManifestPath (Join-Path $reports 'visual_manifest.json')
$inventory = Get-RouteInventory -RouteMap $routeMap -LiveMap $liveMap
$findings = Get-VisualFindings $inventory
$scores = Get-RouteScores $inventory
$types = Get-PageTypeAudit $inventory
$repoAudit = Get-RepoAudit -Mode $Mode -RootPath $TargetPath -inventory $inventory
$decision = Decide -scores $scores -findings $findings -inventory $inventory
$howToFix = [pscustomobject]@{ mode=$Mode; root=$TargetPath; steps=$decision.do }
$priority = @()
foreach($item in $decision.p0){ $priority += 'P0: ' + $item }
foreach($item in $decision.p1){ $priority += 'P1: ' + $item }
if($priority.Count -eq 0){ $priority += 'No priority issues detected by baseline rules.' }

$inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'route_inventory.json') -Encoding UTF8
$findings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'visual_findings.json') -Encoding UTF8
$scores | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'route_scores.json') -Encoding UTF8
$types | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'page_type_audit.json') -Encoding UTF8
$repoAudit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'repo_audit.json') -Encoding UTF8
$decision | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'decision_summary.json') -Encoding UTF8
$howToFix | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reports 'HOW_TO_FIX.json') -Encoding UTF8
Write-Report -Decision $decision -Inventory $inventory -Findings $findings -OutPath (Join-Path $reports 'REPORT.txt') -Mode $Mode -TargetRoot $TargetPath
Write-TextFile -Path (Join-Path $reports '00_PRIORITY_ACTIONS.txt') -Lines $priority
Write-TextFile -Path (Join-Path $reports '01_TOP_ISSUES.txt') -Lines $priority
Write-TextFile -Path (Join-Path $reports '11A_EXECUTIVE_SUMMARY.txt') -Lines @('CORE PROBLEM: ' + $decision.core, 'MODE: ' + $Mode, 'ROOT: ' + $TargetPath)
Write-Host 'DONE'
