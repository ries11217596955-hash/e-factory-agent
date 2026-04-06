$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Normalize { param($x) return @($x) }

function Get-Path {
    param($i)
    if ($i.route_path) { return [string]$i.route_path }
    try { return ([uri]$i.url).AbsolutePath } catch { return [string]$i.url }
}

function Get-Int { param($v) try { return [int]$v } catch { return 0 } }

function Get-Weight {
    param([string]$p)
    if ($p -in @("/", "/hubs/", "/search/")) { return "critical" }
    if ($p -in @("/tools/", "/start-here/")) { return "high" }
    return "normal"
}

function Get-RouteInventory {
    param($items)
    $out = @()
    foreach ($i in (Normalize $items)) {
        $p = Get-Path $i
        $out += [pscustomobject]@{
            path = $p
            url  = [string]$i.url
            title = [string]$i.title
            bodyTextLength = Get-Int $i.bodyTextLength
            links = Get-Int $i.links
            images = Get-Int $i.images
            screenshotCount = Get-Int $i.screenshotCount
            contentMetricsPresent = [bool]$i.contentMetricsPresent
            weight = Get-Weight $p
        }
    }
    return $out
}

function Get-VisualFindings {
    param($items)
    $out = @()
    foreach ($i in (Normalize $items)) {
        $len = Get-Int $i.bodyTextLength
        $links = Get-Int $i.links
        $img = Get-Int $i.images
        $p = Get-Path $i
        $visual = "ok"

        if ($len -lt 220) { $visual = "empty" }
        elseif ($len -lt 700) { $visual = "thin" }
        elseif ($links -lt 2) { $visual = "weak" }

        $out += [pscustomobject]@{
            path = $p
            visual = $visual
            len = $len
            links = $links
            img = $img
        }
    }
    return $out
}

function Get-RouteScores {
    param($items)
    $out = @()
    foreach ($i in (Normalize $items)) {
        $p=Get-Path $i
        $len=Get-Int $i.bodyTextLength
        $links=Get-Int $i.links

        $band="ok"
        if($len -lt 220){$band="bad"}
        elseif($len -lt 700){$band="thin"}
        elseif($links -lt 2){$band="weak"}

        $out += [pscustomobject]@{
            path=$p
            weight=Get-Weight $p
            band=$band
            len=$len
            links=$links
        }
    }
    return $out
}

function Get-PageTypeAudit {
    param($items)
    $out = @()
    foreach($i in (Normalize $items)){
        $p = Get-Path $i
        $len = Get-Int $i.bodyTextLength
        $links = Get-Int $i.links

        $state = "WEAK"
        if($len -lt 220){ $state = "EMPTY" }
        elseif($len -lt 700){ $state = "THIN" }
        elseif($links -lt 2){ $state = "WEAK" }
        else { $state = "OK" }

        $out += [pscustomobject]@{
            path = $p
            state = $state
            text_length = $len
            links = $links
        }
    }
    return $out
}

function Get-RepoAudit {
    param($inventory)
    return [pscustomobject]@{
        mode = "LIVE_URL"
        repo_bound = $false
        target_root = $null
        notes = @(
            "This contour audits the live deployed site.",
            "Repo-layer audit is not active in the restored cloud baseline."
        )
        routes_seen = @($inventory).Count
    }
}

function Analyze-System {
    param($scores,$findings)

    $router=$false
    $flow=$false
    $next=$false

    foreach($s in $scores){
        if($s.path -eq "/hubs/"){ $router=$true }
        if($s.path -eq "/search/"){ $flow=$true }
    }

    foreach($f in $findings){
        if($f.len -gt 200){ $next=$true }
    }

    return [pscustomobject]@{
        router=$router
        flow=$flow
        next_step=$next
    }
}

function Decide {
    param($scores,$findings)

    $sys=Analyze-System $scores $findings

    $crit=@()
    foreach($s in $scores){
        if($s.weight -eq "critical" -and $s.band -ne "ok"){
            $crit += $s.path
        }
    }

    $core="Site exists but is not a functional system."

    if(-not $sys.router -or -not $sys.flow){
        $core="Site does not function as a decision system (no routing / flow)."
    }
    elseif($crit.Count -gt 0){
        $core="Critical routes are shallow and break navigation."
    }

    $p0=@()

    if(-not $sys.router){
        $p0 += "No router layer (hubs missing)"
    }
    if(-not $sys.flow){
        $p0 += "No discovery flow (search not working)"
    }
    if($crit.Count -gt 0){
        $p0 += "Critical routes shallow: " + ($crit -join ", ")
    }

    $p1=@()
    $thinHigh=@()
    foreach($s in $scores){
        if($s.weight -eq "high" -and $s.band -ne "ok"){
            $thinHigh += $s.path
        }
    }
    if($thinHigh.Count -gt 0){
        $p1 += "High-value routes need more depth: " + ($thinHigh -join ", ")
    }

    $do=@()
    if($crit -contains "/hubs/"){ $do += "Build hubs as router" }
    if($crit -contains "/search/"){ $do += "Fix search as entry" }
    if($thinHigh.Count -gt 0){ $do += "Strengthen tools/start-here as guided routes" }

    $p0 = $p0 | Select-Object -First 3
    $p1 = $p1 | Select-Object -First 3
    $do = $do | Select-Object -First 3

    return [pscustomobject]@{
        core = $core
        p0 = $p0
        p1 = $p1
        do = $do
    }
}

function Write-Report {
    param($Decision, $Inventory, $Findings, [string]$OutPath)

    $criticalCount = (@($Inventory | Where-Object { $_.weight -eq "critical" })).Count
    $badCount = (@($Findings | Where-Object { $_.visual -in @("empty","thin") })).Count

    $lines = @()
    $lines += "SITE STAGE:"
    $lines += "Structure / routing baseline"
    $lines += ""
    $lines += "CORE PROBLEM:"
    $lines += [string]$Decision.core
    $lines += ""
    $lines += "P0:"
    if(@($Decision.p0).Count -eq 0){ $lines += "- none" } else { $Decision.p0 | ForEach-Object { $lines += "- $_" } }
    $lines += ""
    $lines += "P1:"
    if(@($Decision.p1).Count -eq 0){ $lines += "- none" } else { $Decision.p1 | ForEach-Object { $lines += "- $_" } }
    $lines += ""
    $lines += "VISUAL SUMMARY:"
    $lines += "- Routes checked: " + @($Inventory).Count
    $lines += "- Critical routes: " + $criticalCount
    $lines += "- Empty/thin routes: " + $badCount
    $lines += ""
    $lines += "DO NEXT:"
    if(@($Decision.do).Count -eq 0){ $lines += "1. Strengthen top routes" } else {
        $n = 1
        foreach($x in $Decision.do){ $lines += "$n. $x"; $n++ }
    }

    Set-Content -LiteralPath $OutPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep  = Join-Path $root "reports"

    if(!(Test-Path -LiteralPath $rep)){
        New-Item -ItemType Directory -Path $rep -Force | Out-Null
    }

    $manifestPath = Join-Path $rep "visual_manifest.json"
    $manifest = Read-JsonFile $manifestPath
    $items = Normalize $manifest

    $inventory = Get-RouteInventory $items
    $find = Get-VisualFindings $items
    $scores = Get-RouteScores $items
    $types = Get-PageTypeAudit $items
    $repoAudit = Get-RepoAudit $inventory
    $dec = Decide $scores $find

    $inventory | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "route_inventory.json") -Encoding UTF8
    $find      | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "visual_findings.json") -Encoding UTF8
    $scores    | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "route_scores.json") -Encoding UTF8
    $types     | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "page_type_audit.json") -Encoding UTF8
    $repoAudit | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "repo_audit.json") -Encoding UTF8
    $dec       | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rep "decision_summary.json") -Encoding UTF8

    Write-Report -Decision $dec -Inventory $inventory -Findings $find -OutPath (Join-Path $rep "REPORT.txt")

    Write-Host "DONE"
}