$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Get-RepoRoot {
    param([string]$StartPath)

    $current = $StartPath
    for ($i = 0; $i -lt 6; $i++) {
        if (-not $current) { break }

        $gitDir = Join-Path $current ".git"
        $pkg = Join-Path $current "package.json"
        $src = Join-Path $current "src"

        if ((Test-Path $gitDir) -or (Test-Path $pkg) -or (Test-Path $src)) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return $StartPath
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Normalize {
    param($x)
    return @($x)
}

function Get-PathFromItem {
    param($i)

    if ($null -ne $i.route_path -and -not [string]::IsNullOrWhiteSpace([string]$i.route_path)) {
        return [string]$i.route_path
    }

    if ($null -ne $i.url -and -not [string]::IsNullOrWhiteSpace([string]$i.url)) {
        try {
            $u = [uri]([string]$i.url)
            if ([string]::IsNullOrWhiteSpace($u.AbsolutePath)) { return "/" }
            return [string]$u.AbsolutePath
        } catch {
            return [string]$i.url
        }
    }

    return ""
}

function Get-Int {
    param($v)
    try { return [int]$v } catch { return 0 }
}

function Get-Weight {
    param([string]$p)

    if ($p -eq "/" -or $p -eq "/hubs/" -or $p -eq "/search/") { return "critical" }
    if ($p -eq "/tools/" -or $p -eq "/start-here/") { return "high" }
    return "normal"
}

function Build-RouteInventory {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $out += [pscustomobject]@{
            path = Get-PathFromItem $i
            length = Get-Int $i.bodyTextLength
            images = Get-Int $i.images
            links = Get-Int $i.links
        }
    }
    return @($out)
}

function Get-Findings {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $len = Get-Int $i.bodyTextLength
        $img = Get-Int $i.images
        $visual = "ok"

        if ($img -eq 0 -and $len -lt 350) {
            $visual = "empty"
        }
        elseif ($img -eq 0) {
            $visual = "weak"
        }

        $out += [pscustomobject]@{
            path = Get-PathFromItem $i
            len = $len
            img = $img
            links = Get-Int $i.links
            visual = $visual
        }
    }

    return @($out)
}

function Get-Scores {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $p = Get-PathFromItem $i
        $len = Get-Int $i.bodyTextLength

        $band = "ok"
        if ($len -lt 350) {
            $band = "bad"
        }
        elseif ($len -lt 700) {
            $band = "thin"
        }

        $out += [pscustomobject]@{
            path = $p
            weight = Get-Weight $p
            band = $band
            len = $len
            images = Get-Int $i.images
            links = Get-Int $i.links
        }
    }

    return @($out)
}

function Test-AnyPath {
    param(
        [string[]]$Candidates
    )

    foreach ($c in (Normalize $Candidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$c)) {
            return $true
        }
    }

    return $false
}

function Find-SuspiciousTopLevelItems {
    param([string]$RepoRoot)

    $hits = @()
    $topItems = Get-ChildItem -Path $RepoRoot -Force

    $namePatterns = @(
        '^BATCH_',
        '^DELETE_LIST',
        '^PATCH_NOTES',
        '^README_APPLY',
        '^SHA256SUMS',
        '^CONTROL_LOOP',
        '^STRATEGY_BOARD',
        '^00__AI__',
        '^00__ALL_MEMORY',
        '\.patch$',
        '^test-',
        '^tmp',
        '^draft',
        '^spec'
    )

    foreach ($item in $topItems) {
        $name = [string]$item.Name
        foreach ($pattern in $namePatterns) {
            if ($name -match $pattern) {
                $hits += $name
                break
            }
        }
    }

    return @($hits | Select-Object -Unique)
}

function Find-MixedLayerDirectories {
    param([string]$RepoRoot)

    $hits = @()
    $dirs = @("scripts", "tools", "test", "docs", ".state", "done", "failed", "good", "inbox", "log", "logs")
    foreach ($d in $dirs) {
        $path = Join-Path $RepoRoot $d
        if (Test-Path $path) {
            $hits += $d
        }
    }

    return @($hits | Select-Object -Unique)
}

function Analyze-RepoHygiene {
    param([string]$RepoRoot)

    $topSuspicious = Find-SuspiciousTopLevelItems -RepoRoot $RepoRoot
    $mixedDirs = Find-MixedLayerDirectories -RepoRoot $RepoRoot

    $repoClean = ($topSuspicious.Count -eq 0)
    $architectureClean = ($mixedDirs.Count -eq 0)

    return [pscustomobject]@{
        repo_root = $RepoRoot
        suspicious_top_level_items = @($topSuspicious)
        mixed_layer_directories = @($mixedDirs)
        repo_clean = $repoClean
        architecture_clean = $architectureClean
    }
}

function Analyze-System {
    param($scores, $findings)

    $router = $false
    $flow = $false
    $nextStep = $false
    $conversion = $false
    $entry = $false
    $visualTrust = $false

    foreach ($s in (Normalize $scores)) {
        if ($s.path -eq "/hubs/" -and $s.band -eq "ok") { $router = $true }
        if ($s.path -eq "/search/" -and $s.band -eq "ok") { $flow = $true }
        if ($s.path -eq "/" -and $s.band -eq "ok") { $entry = $true }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.len -gt 500) { $nextStep = $true }
        if ($f.img -gt 0) { $visualTrust = $true }
        if ($f.path -match "/pricing/|/contact/|/demo/|/consult|/signup|/subscribe|/start-here/") {
            $conversion = $true
        }
    }

    return [pscustomobject]@{
        system_exists = ($router -and $flow -and $nextStep)
        entry_exists = $entry
        router_exists = $router
        flow_exists = $flow
        next_step_exists = $nextStep
        conversion_exists = $conversion
        visual_trust_exists = $visualTrust
    }
}

function Join-ListText {
    param($items)
    $arr = @()
    foreach ($i in (Normalize $items)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$i)) {
            $arr += [string]$i
        }
    }
    return ($arr -join ", ")
}

function Decide {
    param($scores, $findings, $repoAudit)

    $sys = Analyze-System -scores $scores -findings $findings

    $criticalBad = @()
    $visualEmpty = @()
    $homepageFailure = $false

    foreach ($s in (Normalize $scores)) {
        if ($s.weight -eq "critical" -and $s.band -ne "ok") {
            $criticalBad += $s.path
        }
        if ($s.path -eq "/" -and $s.band -ne "ok") {
            $homepageFailure = $true
        }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.visual -eq "empty") {
            $visualEmpty += $f.path
        }
    }

    $failedGates = @()

    if (-not $sys.system_exists) { $failedGates += "SYSTEM" }
    if (-not $sys.entry_exists) { $failedGates += "ENTRY" }
    if (-not $sys.router_exists) { $failedGates += "ROUTER" }
    if (-not $sys.flow_exists) { $failedGates += "FLOW" }
    if (-not $sys.conversion_exists) { $failedGates += "CONVERSION" }
    if (-not $sys.visual_trust_exists) { $failedGates += "VISUAL" }
    if (-not $repoAudit.repo_clean) { $failedGates += "REPO_CLEANLINESS" }
    if (-not $repoAudit.architecture_clean) { $failedGates += "ARCHITECTURE" }

    $core = "Site does not function as a decision system."
    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $core = "Repo is not a clean product boundary and mixes product with internal/dev artifacts."
    }
    elseif (-not $sys.system_exists) {
        $core = "Site does not function as a decision system."
    }
    elseif ($criticalBad.Count -gt 0) {
        $core = "Critical routes lack sufficient depth and break navigation flow."
    }

    $p0 = @()

    if (-not $repoAudit.repo_clean) {
        $p0 += "Repo cleanliness failed: internal or build artifacts are present in the product repo."
    }
    if (-not $repoAudit.architecture_clean) {
        $p0 += "Architecture boundary failed: product content is mixed with scripts/tools/test layers."
    }
    if (-not $sys.entry_exists) {
        $p0 += "Homepage does not function as a usable entry point."
    }
    if (-not $sys.router_exists) {
        $p0 += "Router layer is missing or ineffective."
    }
    if (-not $sys.flow_exists) {
        $p0 += "Discovery flow is missing or ineffective."
    }
    if (-not $sys.conversion_exists) {
        $p0 += "Conversion layer is missing."
    }
    if (-not $sys.visual_trust_exists) {
        $p0 += "Visual trust layer is missing on key pages."
    }
    if ($criticalBad.Count -gt 0) {
        $p0 += "Critical routes lack depth (" + (Join-ListText $criticalBad) + ")."
    }
    if ($homepageFailure) {
        $p0 += "Homepage lacks sufficient content depth and visual structure."
    }
    if ($visualEmpty.Count -gt 0) {
        $p0 += "Some key routes appear empty (" + (Join-ListText $visualEmpty) + ")."
    }

    $p0 = @($p0 | Select-Object -Unique | Select-Object -First 8)

    $p1 = @()
    $p1 += "No dedicated monetization or conversion route detected in the current structure."
    if ($criticalBad -contains "/hubs/") {
        $p1 += "Hubs behave like a thin page, not a real router."
    }
    if ($criticalBad -contains "/search/") {
        $p1 += "Search behaves like a thin utility page, not a discovery system."
    }
    $p1 = @($p1 | Select-Object -Unique | Select-Object -First 4)

    $do = @()
    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $do += "Separate product files from internal, batch, test, and governance artifacts in the repo."
    }
    if (-not $sys.entry_exists) {
        $do += "Rebuild homepage as entry point with value statement, route options, and next action."
    }
    if (-not $sys.router_exists -or ($criticalBad -contains "/hubs/")) {
        $do += "Rebuild /hubs/ as an intent-based router, not a flat list."
    }
    if (-not $sys.flow_exists -or ($criticalBad -contains "/search/")) {
        $do += "Rebuild /search/ as a discovery flow with guidance and entry points."
    }
    if (-not $sys.conversion_exists) {
        $do += "Add a visible conversion layer on key pages."
    }
    if (-not $sys.visual_trust_exists) {
        $do += "Add visual trust blocks, previews, or screenshots on key pages."
    }
    $do = @($do | Select-Object -Unique | Select-Object -First 3)

    $readiness = [pscustomobject]@{
        indexing = "NO"
        traffic = "NO"
        monetization = "NO"
    }

    if ($sys.system_exists -and $sys.entry_exists -and $sys.router_exists -and $sys.flow_exists) {
        $readiness.indexing = "PARTIAL"
        $readiness.traffic = "PARTIAL"
    }

    if ($sys.conversion_exists) {
        $readiness.monetization = "PARTIAL"
    }

    $missing = @()
    if (-not $sys.router_exists) { $missing += "router_layer" }
    if (-not $sys.flow_exists) { $missing += "discovery_flow" }
    if (-not $sys.conversion_exists) { $missing += "conversion_layer" }
    if (-not $sys.visual_trust_exists) { $missing += "visual_trust_layer" }
    if (-not $sys.entry_exists) { $missing += "entry_structure" }
    $missing = @($missing | Select-Object -Unique)

    return [pscustomobject]@{
        system_verdict = "FAIL"
        failed_gates = @($failedGates | Select-Object -Unique)
        core = $core
        p0 = @($p0)
        p1 = @($p1)
        do = @($do)
        readiness = $readiness
        missing_components = @($missing)
        repo_audit = $repoAudit
        system_status = $sys
    }
}

function Write-DecisionText {
    param([string]$Path, $dec)

    $lines = @()
    $lines += "SYSTEM VERDICT"
    $lines += $dec.system_verdict
    $lines += ""
    $lines += "FAILED GATES"
    foreach ($x in (Normalize $dec.failed_gates)) { $lines += "- $x" }
    $lines += ""
    $lines += "CORE"
    $lines += $dec.core
    $lines += ""
    $lines += "P0"
    foreach ($x in (Normalize $dec.p0)) { $lines += "- $x" }
    $lines += ""
    $lines += "P1"
    foreach ($x in (Normalize $dec.p1)) { $lines += "- $x" }
    $lines += ""
    $lines += "DO NEXT"
    $i = 1
    foreach ($x in (Normalize $dec.do)) {
        $lines += ("{0}. {1}" -f $i, $x)
        $i++
    }
    $lines += ""
    $lines += "READINESS"
    $lines += ("indexing: " + $dec.readiness.indexing)
    $lines += ("traffic: " + $dec.readiness.traffic)
    $lines += ("monetization: " + $dec.readiness.monetization)
    $lines += ""
    $lines += "MISSING COMPONENTS"
    foreach ($x in (Normalize $dec.missing_components)) { $lines += "- $x" }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep = Join-Path $root "reports"
    if (-not (Test-Path $rep)) {
        New-Item -ItemType Directory -Path $rep | Out-Null
    }

    $repoRoot = Get-RepoRoot -StartPath $root
    $repoAudit = Analyze-RepoHygiene -RepoRoot $repoRoot

    $manifestPath = Join-Path $rep "visual_manifest.json"
    $manifest = Read-JsonFile -Path $manifestPath

    $items = Normalize $manifest
    $inventory = Build-RouteInventory -items $items
    $find = Get-Findings -items $items
    $scores = Get-Scores -items $items
    $dec = Decide -scores $scores -findings $find -repoAudit $repoAudit

    $inventory | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "route_inventory.json") -Encoding UTF8
    $find | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "visual_findings.json") -Encoding UTF8
    $scores | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "route_scores.json") -Encoding UTF8
    $repoAudit | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "repo_audit.json") -Encoding UTF8
    $dec | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $rep "decision_summary.json") -Encoding UTF8
    Write-DecisionText -Path (Join-Path $rep "REPORT.txt") -dec $dec

    Write-Host "DONE"
}
