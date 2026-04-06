param(
    [ValidateSet("REPO", "ZIP", "URL")]
    [string]$AuditMode = "REPO",
    [string]$TargetPath,
    [string]$BaseUrl
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Normalize($x) { return @($x) }

function Get-Int($v) { try { return [int]$v } catch { return 0 } }

function RelPath([string]$Root, [string]$Full) {
    try {
        return [IO.Path]::GetRelativePath($Root, $Full).Replace('\\','/')
    } catch {
        return $Full
    }
}

function Get-Weight([string]$p) {
    if ($p -in @('/', '/hubs/', '/search/')) { return 'critical' }
    if ($p -in @('/tools/', '/start-here/')) { return 'high' }
    return 'normal'
}

function Find-FirstFile {
    param([string]$Root, [string[]]$Candidates)
    foreach ($c in $Candidates) {
        $full = Join-Path $Root $c
        if (Test-Path -LiteralPath $full) { return $full }
    }
    return $null
}

function Test-MeaningfulFile([string]$Path) {
    if (-not $Path) { return $false }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return (-not [string]::IsNullOrWhiteSpace($text))
    } catch {
        return $false
    }
}

function Measure-FileText([string]$Path) {
    if (-not $Path) { return 0 }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return $text.Length
    } catch {
        return 0
    }
}

function Count-LinkTokens([string]$Path) {
    if (-not $Path) { return 0 }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $matches = [regex]::Matches($text, '\[[^\]]+\]\([^\)]+\)')
        return $matches.Count
    } catch {
        return 0
    }
}

function Get-RouteCandidates {
    return @(
        [pscustomobject]@{ path='/'            ; candidates=@('src/index.md','src/index.njk','src/index.html','index.md','index.njk','index.html') },
        [pscustomobject]@{ path='/hubs/'       ; candidates=@('src/hubs/index.md','src/hubs/index.njk','src/hubs/index.html','hubs/index.md','hubs/index.njk','hubs/index.html') },
        [pscustomobject]@{ path='/tools/'      ; candidates=@('src/tools/index.md','src/tools/index.njk','src/tools/index.html','tools/index.md','tools/index.njk','tools/index.html') },
        [pscustomobject]@{ path='/start-here/' ; candidates=@('src/start-here/index.md','src/start-here/index.njk','src/start-here/index.html','start-here/index.md','start-here/index.njk','start-here/index.html') },
        [pscustomobject]@{ path='/search/'     ; candidates=@('src/search/index.md','src/search.njk','src/search.html','search/index.md','search/index.njk','search/index.html') }
    )
}

function Get-RouteInventoryFromRepo {
    param([string]$RepoRoot)

    $out = @()
    foreach ($r in Get-RouteCandidates) {
        $file = Find-FirstFile -Root $RepoRoot -Candidates $r.candidates
        $exists = [bool]$file
        $len = Measure-FileText $file
        $links = Count-LinkTokens $file
        $out += [pscustomobject]@{
            path = $r.path
            source = 'repo'
            file = if ($file) { RelPath $RepoRoot $file } else { $null }
            exists = $exists
            title = if ($file) { [IO.Path]::GetFileName($file) } else { '' }
            bodyTextLength = $len
            links = $links
            images = 0
            screenshotCount = 0
            contentMetricsPresent = $exists
            weight = Get-Weight $r.path
        }
    }
    return $out
}

function Merge-LiveIntoInventory {
    param($Inventory, $LiveItems)

    $map = @{}
    foreach ($item in $Inventory) { $map[$item.path] = $item }

    foreach ($l in (Normalize $LiveItems)) {
        $p = [string]$l.route_path
        if (-not $p) {
            try { $p = ([uri]$l.url).AbsolutePath } catch { $p = [string]$l.url }
        }
        if (-not $map.ContainsKey($p)) { continue }

        $base = $map[$p]
        $map[$p] = [pscustomobject]@{
            path = $base.path
            source = 'repo+live'
            file = $base.file
            exists = $base.exists
            title = if ($l.title) { [string]$l.title } else { $base.title }
            bodyTextLength = if ((Get-Int $l.bodyTextLength) -gt 0) { Get-Int $l.bodyTextLength } else { $base.bodyTextLength }
            links = [Math]::Max($base.links, (Get-Int $l.links))
            images = Get-Int $l.images
            screenshotCount = Get-Int $l.screenshotCount
            contentMetricsPresent = [bool]($base.contentMetricsPresent -or $l.contentMetricsPresent)
            weight = $base.weight
            live_url = [string]$l.url
            live_status = [string]$l.status
        }
    }

    return @($map.Values | Sort-Object path)
}

function Get-VisualBand($exists, $len, $links) {
    if (-not $exists) { return 'missing' }
    if ($len -lt 120) { return 'empty' }
    if ($len -lt 500) { return 'thin' }
    if ($links -lt 1) { return 'weak' }
    return 'ok'
}

function Get-VisualFindings($items) {
    $out = @()
    foreach ($i in (Normalize $items)) {
        $band = Get-VisualBand $i.exists (Get-Int $i.bodyTextLength) (Get-Int $i.links)
        $out += [pscustomobject]@{
            path = $i.path
            visual = $band
            len = Get-Int $i.bodyTextLength
            links = Get-Int $i.links
            img = Get-Int $i.images
            exists = [bool]$i.exists
            screenshotCount = Get-Int $i.screenshotCount
            source = [string]$i.source
        }
    }
    return $out
}

function Get-RouteScores($items) {
    $out = @()
    foreach ($i in (Normalize $items)) {
        $band = Get-VisualBand $i.exists (Get-Int $i.bodyTextLength) (Get-Int $i.links)
        $out += [pscustomobject]@{
            path = $i.path
            weight = Get-Weight $i.path
            band = $band
            len = Get-Int $i.bodyTextLength
            links = Get-Int $i.links
            exists = [bool]$i.exists
            source = [string]$i.source
        }
    }
    return $out
}

function Get-PageTypeAudit($items) {
    $out = @()
    foreach ($i in (Normalize $items)) {
        $band = Get-VisualBand $i.exists (Get-Int $i.bodyTextLength) (Get-Int $i.links)
        $state = switch ($band) {
            'missing' { 'MISSING' }
            'empty'   { 'EMPTY' }
            'thin'    { 'THIN' }
            'weak'    { 'WEAK' }
            default   { 'OK' }
        }
        $out += [pscustomobject]@{
            path = $i.path
            state = $state
            text_length = Get-Int $i.bodyTextLength
            links = Get-Int $i.links
            exists = [bool]$i.exists
            source = [string]$i.source
        }
    }
    return $out
}

function Get-RepoAudit {
    param([string]$Mode, [string]$TargetRoot, $Inventory, [bool]$LiveCaptureUsed)

    return [pscustomobject]@{
        mode = $Mode
        repo_bound = [bool]($Mode -in @('REPO','ZIP'))
        target_root = $TargetRoot
        live_capture_used = $LiveCaptureUsed
        routes_seen = @($Inventory).Count
        routes_missing = @($Inventory | Where-Object { -not $_.exists } | Select-Object -ExpandProperty path)
    }
}

function Decide($scores, $findings, [string]$Mode, [bool]$LiveCaptureUsed) {
    $missingCritical = @($scores | Where-Object { $_.weight -eq 'critical' -and $_.band -eq 'missing' } | Select-Object -ExpandProperty path)
    $weakCritical    = @($scores | Where-Object { $_.weight -eq 'critical' -and $_.band -in @('empty','thin','weak') } | Select-Object -ExpandProperty path)
    $weakHigh        = @($scores | Where-Object { $_.weight -eq 'high' -and $_.band -ne 'ok' } | Select-Object -ExpandProperty path)

    $core = switch ($Mode) {
        'ZIP'  { 'ZIP audit completed.' }
        'REPO' { 'Repo audit completed.' }
        default { 'URL audit completed.' }
    }
    if ($missingCritical.Count -gt 0) {
        $core = 'Critical routes are missing.'
    } elseif ($weakCritical.Count -gt 0) {
        $core = 'Critical routes exist but are weak.'
    }

    $p0 = @()
    if ($missingCritical.Count -gt 0) {
        $p0 += 'Missing critical routes: ' + ($missingCritical -join ', ')
    }
    if ($weakCritical.Count -gt 0) {
        $p0 += 'Weak critical routes: ' + ($weakCritical -join ', ')
    }

    $p1 = @()
    if ($weakHigh.Count -gt 0) {
        $p1 += 'High-value routes need work: ' + ($weakHigh -join ', ')
    }
    if ($Mode -eq 'REPO' -and -not $LiveCaptureUsed) {
        $p1 += 'Live capture did not run in REPO mode.'
    }

    $do = @()
    if ($missingCritical.Count -gt 0) { $do += 'Restore missing critical routes first.' }
    if ($weakCritical.Count -gt 0) { $do += 'Strengthen critical routes with real content.' }
    if ($weakHigh.Count -gt 0) { $do += 'Improve /tools/ and /start-here/ depth.' }
    if ($Mode -eq 'ZIP') { $do += 'Keep ZIP audit file-only and stable.' }
    if ($Mode -eq 'REPO') { $do += 'Keep REPO audit separate from inbox ZIP.' }

    return [pscustomobject]@{
        core = $core
        p0 = @($p0 | Select-Object -First 3)
        p1 = @($p1 | Select-Object -First 3)
        do = @($do | Select-Object -First 3)
    }
}

function Write-Report {
    param($Decision, $Inventory, $Findings, $RepoAudit, [string]$OutPath)

    $lines = @()
    $lines += 'STATUS:'
    $lines += 'PASS'
    $lines += ''
    $lines += 'MODE:'
    $lines += [string]$RepoAudit.mode
    $lines += ''
    $lines += 'CORE PROBLEM:'
    $lines += [string]$Decision.core
    $lines += ''
    $lines += 'P0:'
    if (@($Decision.p0).Count -eq 0) { $lines += '- none' } else { $Decision.p0 | ForEach-Object { $lines += '- ' + $_ } }
    $lines += ''
    $lines += 'P1:'
    if (@($Decision.p1).Count -eq 0) { $lines += '- none' } else { $Decision.p1 | ForEach-Object { $lines += '- ' + $_ } }
    $lines += ''
    $lines += 'SUMMARY:'
    $lines += '- Routes checked: ' + @($Inventory).Count
    $lines += '- Missing routes: ' + @($Findings | Where-Object { $_.visual -eq 'missing' }).Count
    $lines += '- Empty/thin routes: ' + @($Findings | Where-Object { $_.visual -in @('empty','thin') }).Count
    $lines += '- Live capture used: ' + [string]$RepoAudit.live_capture_used
    $lines += ''
    $lines += 'DO NEXT:'
    if (@($Decision.do).Count -eq 0) {
        $lines += '1. Keep improving top routes.'
    } else {
        $i = 1
        foreach ($x in $Decision.do) { $lines += ("{0}. {1}" -f $i, $x); $i++ }
    }
    Set-Content -LiteralPath $OutPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
}

function Invoke-LiveCapture {
    param([string]$Root, [string]$BaseUrl)
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return $null }

    $capPath = Join-Path $Root 'capture.mjs'
    if (-not (Test-Path -LiteralPath $capPath)) { return $null }

    $env:BASE_URL = $BaseUrl
    try {
        Push-Location $Root
        & node $capPath
        Pop-Location
    } catch {
        try { Pop-Location } catch {}
        return $null
    }

    $manifestPath = Join-Path $Root 'reports/visual_manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    return Read-JsonFile $manifestPath
}

function Invoke-SiteAuditor {
    param([string]$AuditMode, [string]$TargetPath, [string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep  = Join-Path $root 'reports'
    $out  = Join-Path $root 'outbox'

    Ensure-Dir $rep
    Ensure-Dir $out

    $inventory = @()
    $liveCaptureUsed = $false
    $liveItems = $null

    switch ($AuditMode) {
        'REPO' {
            if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not (Test-Path -LiteralPath $TargetPath)) {
                throw 'REPO mode requires an existing TargetPath'
            }
            $inventory = Get-RouteInventoryFromRepo -RepoRoot $TargetPath
            $liveItems = Invoke-LiveCapture -Root $root -BaseUrl $BaseUrl
            if ($liveItems) {
                $inventory = Merge-LiveIntoInventory -Inventory $inventory -LiveItems $liveItems
                $liveCaptureUsed = $true
            }
        }
        'ZIP' {
            if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not (Test-Path -LiteralPath $TargetPath)) {
                throw 'ZIP mode requires an existing TargetPath'
            }
            $inventory = Get-RouteInventoryFromRepo -RepoRoot $TargetPath
        }
        'URL' {
            $liveItems = Invoke-LiveCapture -Root $root -BaseUrl $BaseUrl
            if (-not $liveItems) {
                throw 'URL mode capture failed'
            }
            $inventory = @()
            foreach ($l in (Normalize $liveItems)) {
                $p = [string]$l.route_path
                if (-not $p) {
                    try { $p = ([uri]$l.url).AbsolutePath } catch { $p = [string]$l.url }
                }
                $inventory += [pscustomobject]@{
                    path = $p
                    source = 'live'
                    file = $null
                    exists = $true
                    title = [string]$l.title
                    bodyTextLength = Get-Int $l.bodyTextLength
                    links = Get-Int $l.links
                    images = Get-Int $l.images
                    screenshotCount = Get-Int $l.screenshotCount
                    contentMetricsPresent = [bool]$l.contentMetricsPresent
                    weight = Get-Weight $p
                    live_url = [string]$l.url
                    live_status = [string]$l.status
                }
            }
            $liveCaptureUsed = $true
        }
    }

    $find = Get-VisualFindings $inventory
    $scores = Get-RouteScores $inventory
    $types = Get-PageTypeAudit $inventory
    $repoAudit = Get-RepoAudit -Mode $AuditMode -TargetRoot $TargetPath -Inventory $inventory -LiveCaptureUsed $liveCaptureUsed
    $dec = Decide -scores $scores -findings $find -Mode $AuditMode -LiveCaptureUsed $liveCaptureUsed

    $inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'route_inventory.json') -Encoding UTF8
    $find      | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'visual_findings.json') -Encoding UTF8
    $scores    | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'route_scores.json') -Encoding UTF8
    $types     | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'page_type_audit.json') -Encoding UTF8
    $repoAudit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'repo_audit.json') -Encoding UTF8
    $dec       | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'decision_summary.json') -Encoding UTF8

    if ($liveCaptureUsed -and $liveItems) {
        $liveItems | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'visual_manifest.json') -Encoding UTF8
    }

    $result = [pscustomobject]@{
        status = 'PASS'
        mode = $AuditMode
        target_root = $TargetPath
        live_capture_used = $liveCaptureUsed
        checked_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $rep 'audit_result.json') -Encoding UTF8

    Write-Report -Decision $dec -Inventory $inventory -Findings $find -RepoAudit $repoAudit -OutPath (Join-Path $rep 'REPORT.txt')

    Set-Content -LiteralPath (Join-Path $out 'DONE.ok') -Value ('PASS ' + $AuditMode) -Encoding UTF8
    Write-Host 'DONE'
}

try {
    Invoke-SiteAuditor -AuditMode $AuditMode -TargetPath $TargetPath -BaseUrl $BaseUrl
} catch {
    $root = Get-ScriptRoot
    $rep  = Join-Path $root 'reports'
    $out  = Join-Path $root 'outbox'
    Ensure-Dir $rep
    Ensure-Dir $out
    $msg = $_.Exception.Message
    $fail = [pscustomobject]@{ status='FAIL'; mode=$AuditMode; error=$msg; checked_at_utc=[DateTime]::UtcNow.ToString('o') }
    $fail | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $rep 'audit_result.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rep 'REPORT.txt') -Value ("STATUS:`nFAIL`n`nMODE:`n$AuditMode`n`nERROR:`n$msg") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $out 'DONE.fail') -Value $msg -Encoding UTF8
    Write-Error $msg
    exit 1
}
