$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Normalize { param($x) return @($x) }

function Get-Path {
    param($i)
    if ($i.route_path) { return $i.route_path }
    try { return ([uri]$i.url).AbsolutePath } catch { return $i.url }
}

function Get-Int { param($v) try { [int]$v } catch { 0 } }

function Get-Weight {
    param($p)
    if ($p -in @("/", "/hubs/", "/search/")) { return "critical" }
    if ($p -in @("/tools/", "/start-here/")) { return "high" }
    return "normal"
}

function Get-Findings {
    param($items)
    $out=@()
    foreach($i in (Normalize $items)){
        $len=Get-Int $i.bodyTextLength
        $img=Get-Int $i.images
        $visual="ok"
        if($img -eq 0 -and $len -lt 350){$visual="empty"}
        elseif($img -eq 0){$visual="weak"}

        $out+=[pscustomobject]@{
            path=Get-Path $i
            len=$len
            img=$img
            visual=$visual
        }
    }
    return $out
}

function Get-Scores {
    param($items)
    $out=@()
    foreach($i in (Normalize $items)){
        $p=Get-Path $i
        $len=Get-Int $i.bodyTextLength
        $band="ok"
        if($len -lt 350){$band="bad"}
        elseif($len -lt 700){$band="thin"}

        $out+=[pscustomobject]@{
            path=$p
            weight=Get-Weight $p
            band=$band
        }
    }
    return $out
}

function Analyze-System {
    param($scores,$findings)

    $router=$false
    $flow=$false
    $next=$false
    $conversion=$false

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
        conversion=$conversion
    }
}

function Decide {
    param($scores,$findings)

    $sys=Analyze-System $scores $findings

    $crit=@()
    foreach($s in $scores){
        if($s.weight -eq "critical" -and $s.band -ne "ok"){
            $crit+=$s.path
        }
    }

    $empty=@()
    foreach($f in $findings){
        if($f.visual -eq "empty"){
            $empty+=$f.path
        }
    }

    $core="Site exists but is not a functional decision system."

    if(-not $sys.router -or -not $sys.flow){
        $core="Site does not function as a decision system due to missing routing and flow."
    }
    elseif($crit.Count -gt 0){
        $core="Critical routes lack sufficient depth and break navigation flow."
    }

    $p0=@()

    if(-not $sys.router){
        $p0+="No router layer detected (hubs missing or ineffective)."
    }
    if(-not $sys.flow){
        $p0+="No usable discovery flow detected (search ineffective)."
    }
    if($crit.Count -gt 0){
        $p0+="Critical routes lack depth ("+($crit -join ", ")+")."
    }
    if($empty.Count -gt 0){
        $p0+="Key routes appear empty ("+($empty -join ", ")+")."
    }

    $p0=$p0|Select-Object -First 4

    $p1=@()
    if(-not $sys.conversion){
        $p1+="No conversion or monetization layer detected."
    }

    $do=@()
    if($crit -contains "/hubs/"){
        $do+="Build hubs as category router with forward links."
    }
    if($crit -contains "/search/"){
        $do+="Turn search into real entry + discovery system."
    }
    if($empty.Count -gt 0){
        $do+="Add structured content blocks to empty pages."
    }

    $do=$do|Select-Object -First 3

    $readiness="NOT READY"
    if($sys.router -and $sys.flow -and $sys.next_step){
        $readiness="PARTIAL"
    }

    return [pscustomobject]@{
        core=$core
        p0=$p0
        p1=$p1
        do=$do
        readiness=$readiness
        system=$sys
    }
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root=Get-ScriptRoot
    $rep=Join-Path $root "reports"
    if(!(Test-Path $rep)){New-Item -ItemType Directory -Path $rep|Out-Null}

    $manifest=Read-JsonFile (Join-Path $rep "visual_manifest.json")

    $items=Normalize $manifest
    $find=Get-Findings $items
    $scores=Get-Scores $items
    $dec=Decide $scores $find

    $dec|ConvertTo-Json -Depth 6|Set-Content (Join-Path $rep "decision_summary.json")

    Write-Host "DONE"
}
