function Build-RouteInventory {
    param([string]$BaseUrl)
    Write-Host "Build-RouteInventory: skipped (handled by capture layer)"
}
# =========================

# SITE AUDITOR AGENT V4.5

# Decision Intelligence Version

# =========================

$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
if ($PSScriptRoot) { return $PSScriptRoot }
if ($PSCommandPath) { return Split-Path $PSCommandPath }
return (Get-Location).Path
}

function Read-JsonFile {
param([string]$Path)
if (-not (Test-Path $Path)) {
throw "File not found: $Path"
}
return Get-Content $Path -Raw | ConvertFrom-Json
}

# -------------------------

# NORMALIZATION

# -------------------------

function Normalize-Items {
param([object]$Items)
return @($Items)
}

# -------------------------

# VISUAL FINDINGS

# -------------------------

function Get-VisualFindings {
param([object[]]$ManifestItems)

```
$items = Normalize-Items $ManifestItems
$result = @()

foreach ($i in $items) {
    $images = if ($i.images) { [int]$i.images } else { 0 }
    $len    = if ($i.bodyTextLength) { [int]$i.bodyTextLength } else { 0 }

    $visualClass = "visual_ok"
    if ($images -eq 0 -and $len -lt 400) {
        $visualClass = "visual_empty"
    }
    elseif ($images -eq 0) {
        $visualClass = "visual_weak"
    }

    $result += [pscustomobject]@{
        route_path = $i.route_path
        visual_class = $visualClass
    }
}

return $result
```

}

# -------------------------

# ROUTE WEIGHT

# -------------------------

function Get-RouteWeight {
param([string]$Path)

```
if ($Path -in @("/", "/hubs/", "/search/")) { return "critical" }
if ($Path -in @("/tools/", "/start-here/")) { return "high" }
return "normal"
```

}

# -------------------------

# ROUTE SCORES

# -------------------------

function Build-RouteScores {
param([object[]]$ManifestItems)

```
$items = Normalize-Items $ManifestItems
$scores = @()

foreach ($i in $items) {
    $len = if ($i.bodyTextLength) { [int]$i.bodyTextLength } else { 0 }

    $band = if ($len -lt 350) { "watch" } else { "ok" }

    $scores += [pscustomobject]@{
        route_path = $i.route_path
        score_band = $band
        weight     = Get-RouteWeight $i.route_path
        length     = $len
    }
}

return $scores
```

}

# -------------------------

# SUMMARY

# -------------------------

function Build-VisualSummary {
param(
[string]$BaseUrl,
[object[]]$ManifestItems,
[object[]]$Findings
)

```
$items = Normalize-Items $ManifestItems
$count = $items.Count

return [pscustomobject]@{
    base_url = $BaseUrl
    route_count = $count
    status = "OK"
}
```

}

# -------------------------

# DECISION ENGINE V4.5

# -------------------------

function New-DecisionSummaryV4 {
param(
[object]$VisualSummary,
[object[]]$RouteScores,
[object[]]$Findings
)

```
$p0 = @()
$p1 = @()
$p2 = @()
$doNext = @()

$hasWeakCritical = $false

foreach ($r in $RouteScores) {
    if ($r.score_band -eq "watch" -and $r.weight -eq "critical") {
        $hasWeakCritical = $true
        $p0 += "$($r.route_path) is a critical route and too shallow"
    }
}

$visualWeak = $Findings | Where-Object { $_.visual_class -ne "visual_ok" }

if ($visualWeak.Count -gt 0) {
    $p0 += "Visual layer is weak across key routes"
}

$stage = "Stage 1: Structure"
if (-not $hasWeakCritical) {
    $stage = "Stage 2: Product"
}

$core = if ($hasWeakCritical) {
    "Critical routes lack depth, breaking navigation flow"
} else {
    "Site structure exists but needs refinement"
}

$doNext = @(
    "Expand hubs into structured navigation",
    "Improve search route content",
    "Add visual elements to key pages"
)

return [pscustomobject]@{
    site_stage = $stage
    core_problem = $core
    p0 = ($p0 -join " | ")
    p1 = ($p1 -join " | ")
    p2 = ($p2 -join " | ")
    do_next = ($doNext -join " | ")
}
```

}

# -------------------------

# MAIN

# -------------------------

function Invoke-SiteAuditor {
param([string]$BaseUrl)

```
$scriptRoot = Get-ScriptRoot
$reportsDir = Join-Path $scriptRoot "reports"

if (-not (Test-Path $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir | Out-Null
}

$manifestPath = Join-Path $scriptRoot "visual_manifest.json"
$manifest = Read-JsonFile $manifestPath

$items = @($manifest)

$findings = Get-VisualFindings -ManifestItems $items
$scores   = Build-RouteScores -ManifestItems $items
$summary  = Build-VisualSummary -BaseUrl $BaseUrl -ManifestItems $items -Findings $findings

$decision = New-DecisionSummaryV4 -VisualSummary $summary -RouteScores $scores -Findings $findings

$decision | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $reportsDir "decision_summary.json")
```

}
