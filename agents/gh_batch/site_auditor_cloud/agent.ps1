$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
if ($PSScriptRoot) { return $PSScriptRoot }
if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
return (Get-Location).Path
}

function Build-RouteInventory {
param([string]$BaseUrl)
Write-Host "Build-RouteInventory: shim"
}

function Read-JsonFile {
param([string]$Path)
if (-not (Test-Path $Path)) { throw "File not found: $Path" }
return Get-Content $Path -Raw | ConvertFrom-Json
}

function Normalize {
param($x)
return @($x)
}

function Get-Path {
param($i)
if ($i.route_path) { return $i.route_path }
try { return ([uri]$i.url).AbsolutePath } catch { return $i.url }
}

function Get-Weight {
param($p)
if ($p -eq "/" -or $p -eq "/hubs/" -or $p -eq "/search/") { return "critical" }
if ($p -eq "/tools/" -or $p -eq "/start-here/") { return "high" }
return "normal"
}

function Get-Int {
param($v)
try { return [int]$v } catch { return 0 }
}

# ---------- FINDINGS ----------

function Get-VisualFindings {
param([object[]]$items)

```
$out = @()
$arr = Normalize $items

foreach ($i in $arr) {
    $len = Get-Int $i.bodyTextLength
    $img = Get-Int $i.images

    $cls = "ok"
    if ($img -eq 0 -and $len -lt 350) {
        $cls = "empty"
    } elseif ($img -eq 0) {
        $cls = "weak"
    }

    $out += [pscustomobject]@{
        path = Get-Path $i
        len  = $len
        img  = $img
        visual = $cls
    }
}

return $out
```

}

# ---------- SCORES ----------

function Build-RouteScores {
param([object[]]$items)

```
$out = @()
$arr = Normalize $items

foreach ($i in $arr) {
    $p = Get-Path $i
    $len = Get-Int $i.bodyTextLength

    $band = "ok"
    if ($len -lt 350) { $band = "bad" }
    elseif ($len -lt 700) { $band = "thin" }

    $out += [pscustomobject]@{
        path = $p
        weight = Get-Weight $p
        band = $band
        len = $len
    }
}

return $out
```

}

# ---------- DECISION ----------

function Decide {
param($scores, $findings)

```
$p0 = @()
$p1 = @()
$do = @()

$crit = @()
foreach ($s in $scores) {
    if ($s.weight -eq "critical" -and $s.band -ne "ok") {
        $crit += $s
    }
}

$visualEmpty = @()
foreach ($f in $findings) {
    if ($f.visual -eq "empty") {
        $visualEmpty += $f
    }
}

# CORE
$core = "Site works but lacks decision strength."
if ($crit.Count -gt 0) {
    $core = "Critical routes are too shallow and break navigation flow."
} elseif ($visualEmpty.Count -gt 0) {
    $core = "Key pages appear empty and reduce trust and scanability."
}

# P0
$count = 0
foreach ($c in $crit) {
    if ($count -ge 3) { break }
    $p0 += "$($c.path) breaks navigation flow due to insufficient depth."
    $count++
}

if ($visualEmpty.Count -gt 0) {
    $p0 += "Key routes appear empty and reduce user trust."
}

# P1
if ($crit.Count -gt 0) {
    $p1 += "Strengthen routing before adding growth features."
}

# DO NEXT
foreach ($c in $crit) {
    if ($c.path -eq "/hubs/") {
        $do += "Expand /hubs/ into structured navigation with categories and forward links."
    }
    if ($c.path -eq "/search/") {
        $do += "Rebuild /search/ as a real discovery page with guidance and entry points."
    }
}

if ($visualEmpty.Count -gt 0) {
    $do += "Add visual blocks to key pages to improve scanability and trust."
}

# LIMIT DO
$do = $do | Select-Object -Unique | Select-Object -First 3

# STAGE
$stage = "Stage 2"
if ($crit.Count -gt 0 -or $visualEmpty.Count -gt 0) {
    $stage = "Stage 1"
}

return [pscustomobject]@{
    stage = $stage
    core  = $core
    p0    = $p0
    p1    = $p1
    do    = $do
}
```

}

# ---------- MAIN ----------

function Invoke-SiteAuditor {
param([string]$BaseUrl)

```
$root = Get-ScriptRoot
Write-Host "scriptRoot: $root"

$rep = Join-Path $root "reports"
if (!(Test-Path $rep)) { New-Item -ItemType Directory -Path $rep | Out-Null }

$manifestPath = Join-Path $rep "visual_manifest.json"
$manifest = Read-JsonFile $manifestPath

$items = Normalize $manifest
$find  = Get-VisualFindings $items
$scores= Build-RouteScores $items
$dec   = Decide $scores $find

$dec | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rep "decision_summary.json")

Write-Host "DONE"
```

}
