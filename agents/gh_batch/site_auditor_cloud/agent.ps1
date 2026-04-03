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
    if ($null -ne $i.route_path -and -not [string]::IsNullOrWhiteSpace([string]$i.route_path)) {
        return [string]$i.route_path
    }
    try { return ([uri]$i.url).AbsolutePath } catch { return [string]$i.url }
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

function Join-NonEmpty {
    param([string[]]$Items, [string]$Separator = ", ")
    $arr = @()
    foreach ($i in (Normalize $Items)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$i)) { $arr += [string]$i }
    }
    return ($arr -join $Separator)
}

function Get-VisualFindings {
    param([object[]]$items)

    $out = @()
    $arr = Normalize $items

    foreach ($i in $arr) {
        $len = Get-Int $i.bodyTextLength
        $img = Get-Int $i.images

        $cls = "ok"
        if ($img -eq 0 -and $len -lt 350) { $cls = "empty" }
        elseif ($img -eq 0) { $cls = "weak" }

        $out += [pscustomobject]@{
            path   = Get-Path $i
            len    = $len
            img    = $img
            visual = $cls
        }
    }

    return $out
}

function Build-RouteScores {
    param([object[]]$items)

    $out = @()
    $arr = Normalize $items

    foreach ($i in $arr) {
        $p = Get-Path $i
        $len = Get-Int $i.bodyTextLength
        $img = Get-Int $i.images

        $band = "ok"
        if ($len -lt 350) { $band = "bad" }
        elseif ($len -lt 700) { $band = "thin" }

        $out += [pscustomobject]@{
            path   = $p
            weight = Get-Weight $p
            band   = $band
            len    = $len
            img    = $img
        }
    }

    return $out
}

function Get-SystemicIssues {
    param($scores, $findings)

    $issues = [ordered]@{
        critical_depth_routes = @()
        high_depth_routes     = @()
        visual_empty_routes   = @()
        visual_weak_routes    = @()
    }

    foreach ($s in (Normalize $scores)) {
        if ($s.weight -eq "critical" -and $s.band -ne "ok") {
            $issues.critical_depth_routes += $s.path
        }
        elseif ($s.weight -eq "high" -and $s.band -eq "bad") {
            $issues.high_depth_routes += $s.path
        }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.visual -eq "empty") {
            $issues.visual_empty_routes += $f.path
        }
        elseif ($f.visual -eq "weak") {
            $issues.visual_weak_routes += $f.path
        }
    }

    return [pscustomobject]$issues
}

function Decide {
    param($scores, $findings)

    $sys = Get-SystemicIssues -scores $scores -findings $findings

    $p0 = @()
    $p1 = @()
    $p2 = @()
    $do = @()
    $missing = @()

    $criticalRoutes = @($sys.critical_depth_routes | Select-Object -Unique)
    $highRoutes = @($sys.high_depth_routes | Select-Object -Unique)
    $visualEmptyRoutes = @($sys.visual_empty_routes | Select-Object -Unique)
    $visualWeakRoutes = @($sys.visual_weak_routes | Select-Object -Unique)

    $hasCriticalDepthFailure = $criticalRoutes.Count -gt 0
    $hasVisualEmpty = $visualEmptyRoutes.Count -gt 0
    $hasVisualWeak = $visualWeakRoutes.Count -gt 0

    $core = "Site works but route quality still limits decision strength."
    if ($hasCriticalDepthFailure) {
        $core = "Critical routes lack sufficient content depth and break navigation flow."
    }
    elseif ($hasVisualEmpty) {
        $core = "Key routes appear empty and reduce trust and scanability."
    }
    elseif ($hasVisualWeak) {
        $core = "Key routes remain visually weak and reduce clarity."
    }

    $stage = "Stage 2"
    if ($hasCriticalDepthFailure -or $hasVisualEmpty) {
        $stage = "Stage 1"
    }

    if ($hasCriticalDepthFailure) {
        $routeList = Join-NonEmpty -Items $criticalRoutes
        $p0 += "Critical routes lack sufficient content depth ($routeList)."
    }

    if ($hasVisualEmpty) {
        $routeList = Join-NonEmpty -Items $visualEmptyRoutes
        $p0 += "Key routes appear empty and reduce trust and scanability ($routeList)."
    }

    if ($highRoutes.Count -gt 0) {
        $routeList = Join-NonEmpty -Items $highRoutes
        $p1 += "Important secondary routes need more depth ($routeList)."
    }

    if ($hasCriticalDepthFailure) {
        $p1 += "Growth or monetization should not be prioritized before routing quality is fixed."
    }
    elseif ($hasVisualWeak) {
        $routeList = Join-NonEmpty -Items $visualWeakRoutes
        $p1 += "Visual weakness still reduces clarity on some routes ($routeList)."
    }

    $missing += "No dedicated monetization or conversion route detected in the audited route set."
    $p2 += "Monetization is still missing, but it is not the first repair priority."

    if ($criticalRoutes -contains "/hubs/") {
        $do += "Expand /hubs/ into category-level navigation with forward links to key destinations."
    }
    if ($criticalRoutes -contains "/search/") {
        $do += "Rebuild /search/ as a real discovery route with guidance, entry points, and clearer search intent."
    }
    if ($hasVisualEmpty) {
        $do += "Add visual support blocks on empty key routes to improve trust and scanability."
    }

    if ($do.Count -eq 0 -and $highRoutes.Count -gt 0) {
        $do += "Increase depth on the highest-value non-critical routes before adding new surfaces."
    }

    $p0 = @($p0 | Select-Object -Unique | Select-Object -First 3)
    $p1 = @($p1 | Select-Object -Unique | Select-Object -First 3)
    $p2 = @($p2 | Select-Object -Unique | Select-Object -First 2)
    $do = @($do | Select-Object -Unique | Select-Object -First 3)
    $missing = @($missing | Select-Object -Unique | Select-Object -First 2)

    return [pscustomobject]@{
        stage                      = $stage
        core                       = $core
        p0                         = $p0
        p1                         = $p1
        p2                         = $p2
        do                         = $do
        missing                    = $missing
        route_weight_signals       = @($criticalRoutes + $highRoutes | Select-Object -Unique)
        visual_empty_routes        = $visualEmptyRoutes
        visual_weak_routes         = $visualWeakRoutes
    }
}

function Write-DecisionText {
    param([string]$Path, $dec)

    $lines = @()
    $lines += "SITE STAGE"
    $lines += $dec.stage
    $lines += ""
    $lines += "CORE PROBLEM"
    $lines += $dec.core
    $lines += ""
    $lines += "P0"
    if (@($dec.p0).Count -gt 0) { foreach ($x in $dec.p0) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "P1"
    if (@($dec.p1).Count -gt 0) { foreach ($x in $dec.p1) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "P2"
    if (@($dec.p2).Count -gt 0) { foreach ($x in $dec.p2) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "MISSING"
    if (@($dec.missing).Count -gt 0) { foreach ($x in $dec.missing) { $lines += "- $x" } } else { $lines += "- none" }
    $lines += ""
    $lines += "DO NEXT"
    $i = 1
    foreach ($x in @($dec.do)) {
        $lines += ("{0}. {1}" -f $i, $x)
        $i++
    }
    if ($i -eq 1) { $lines += "1. none" }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    Write-Host ("scriptRoot: " + $root)

    $rep = Join-Path $root "reports"
    if (!(Test-Path $rep)) {
        New-Item -ItemType Directory -Path $rep | Out-Null
    }

    $manifestPath = Join-Path $rep "visual_manifest.json"
    $manifest = Read-JsonFile $manifestPath

    $items = Normalize $manifest
    $find  = Get-VisualFindings $items
    $scores = Build-RouteScores $items
    $dec = Decide $scores $find

    $find | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "visual_findings.json")
    $scores | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "route_scores.json")
    $dec | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "decision_summary.json")
    Write-DecisionText -Path (Join-Path $rep "REPORT.txt") -dec $dec

    Write-Host "DONE"
}
