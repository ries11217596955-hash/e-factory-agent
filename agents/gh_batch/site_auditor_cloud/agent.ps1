param(
    [string]$TargetPath,
    [string]$OutDir
)

function Get-AllHtmlFiles {
    param($root)
    Get-ChildItem -Path $root -Recurse -Include *.html,*.htm -ErrorAction SilentlyContinue
}

function Read-TextContent {
    param($file)
    try { return Get-Content $file.FullName -Raw } catch { return "" }
}

function Detect-CTA {
    param($text)
    $patterns = @("get started","start","try","use","buy","sign up","download","learn more","continue")
    foreach ($p in $patterns) { if ($text -match $p) { return $true } }
    return $false
}

function Detect-Contamination {
    param($text)
    $bad = @("built with","edit on github","batch-","localhost","debug")
    foreach ($b in $bad) { if ($text -match $b) { return $true } }
    return $false
}

function Get-Len {
    param($text)
    return ($text -replace "\s","").Length
}

function Classify {
    param($text)

    $len = Get-Len $text
    $cta = Detect-CTA $text
    $bad = Detect-Contamination $text

    if ($len -lt 200) { return "EMPTY" }
    if (-not $cta -and $len -lt 1500) { return "THIN" }
    if ($bad) { return "BROKEN" }
    return "WEAK"
}

function Score {
    param($text)

    return @{
        entry = if ($text.Length -gt 300) {1}else{0}
        flow  = if (Detect-CTA $text) {1}else{0}
        trust = if (Detect-Contamination $text) {0}else{1}
    }
}

$files = Get-AllHtmlFiles $TargetPath
$pages = @()

foreach ($f in $files) {
    $text = Read-TextContent $f
    $state = Classify $text
    $s = Score $text

    $pages += [PSCustomObject]@{
        path=$f.FullName
        state=$state
        entry=$s.entry
        flow=$s.flow
        trust=$s.trust
    }
}

# decision
$p0=@(); $p1=@()

if (($pages | Where {$_.state -eq "EMPTY"}).Count -gt 0) { $p0+="Empty pages exist" }
if (($pages | Where {$_.flow -eq 0}).Count -gt 2) { $p0+="No clear CTA across pages" }
if (($pages | Where {$_.trust -eq 0}).Count -gt 0) { $p0+="UI contamination visible" }

if (($pages | Where {$_.state -eq "THIN"}).Count -gt 1) { $p1+="Thin content pages" }
if (($pages | Where {$_.entry -eq 0}).Count -gt 1) { $p1+="Weak entry clarity" }

$p0 = $p0 | Select -First 3
$p1 = $p1 | Select -First 3

$core = "Site lacks clear user flow and action direction"

# REPORT
$r=@()
$r+="CORE PROBLEM:"; $r+=$core; $r+=""
$r+="P0:"; $p0|%{$r+="- $_"}; $r+=""
$r+="P1:"; $p1|%{$r+="- $_"}; $r+=""
$r+="DO NEXT:"
$r+="1. Add one clear CTA"
$r+="2. Remove UI contamination"
$r+="3. Expand thin pages"

# FIX
$f=@()

if ($p0 -contains "No clear CTA across pages") {
$f+=@"
PROBLEM:
No clear CTA

FIX:
Add primary CTA

WHERE:
Homepage + hubs

HOW:
Button under headline
"@
}

if ($p0 -contains "UI contamination visible") {
$f+=@"
PROBLEM:
UI contamination

FIX:
Remove dev artifacts

WHERE:
Visible UI

HOW:
Delete 'Built with', 'Edit on GitHub'
"@
}

if ($p1 -contains "Thin content pages") {
$f+=@"
PROBLEM:
Thin pages

FIX:
Add structure

WHERE:
All thin pages

HOW:
Add problem + solution + next step
"@
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$r | Out-File "$OutDir\REPORT.txt" -Encoding utf8
$f | Out-File "$OutDir\FIX.txt" -Encoding utf8
$pages | ConvertTo-Json -Depth 5 | Out-File "$OutDir\page_type_audit.json"

Write-Output "AUDIT+FIX DONE"
