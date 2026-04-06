param(
    [string]$TargetPath,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"

function Get-HtmlFiles {
    param($root)
    Get-ChildItem -Path $root -Recurse -Include *.html,*.htm -ErrorAction SilentlyContinue
}

function Read-Text {
    param($file)
    try { return Get-Content $file.FullName -Raw } catch { return "" }
}

function Detect-CTA {
    param($text)
    $patterns = @("get started","start","try","use","buy","sign up","download","learn more","continue")
    foreach ($p in $patterns) {
        if ($text -match $p) { return $true }
    }
    return $false
}

function Detect-Contamination {
    param($text)
    $bad = @("built with","edit on github","batch-","localhost","debug")
    foreach ($b in $bad) {
        if ($text -match $b) { return $true }
    }
    return $false
}

function Classify {
    param($text)

    $len = ($text -replace "\s","").Length
    $cta = Detect-CTA $text
    $bad = Detect-Contamination $text

    if ($len -lt 200) { return "EMPTY" }
    if (-not $cta -and $len -lt 1500) { return "THIN" }
    if ($bad) { return "BROKEN" }
    return "WEAK"
}

# ===== SCAN =====

$files = Get-HtmlFiles $TargetPath
$pages = @()

foreach ($f in $files) {
    $text = Read-Text $f
    $state = Classify $text

    $pages += [PSCustomObject]@{
        path  = $f.FullName
        state = $state
    }
}

# ===== VISUAL LAYER =====

$Capture = Join-Path $PSScriptRoot "capture.mjs"

$ScreensDir = Join-Path $OutDir "screenshots"
New-Item -ItemType Directory -Force -Path $ScreensDir | Out-Null

$VisualEnabled = $false

if (Test-Path $Capture) {
    try {
        Write-Output "VISUAL: running capture.mjs"
        node $Capture $TargetPath $ScreensDir
        $VisualEnabled = $true
    } catch {
        Write-Output "VISUAL FAILED"
    }
}

# ===== DECISION =====

$p0=@()
$p1=@()

if (($pages | Where-Object {$_.state -eq "EMPTY"}).Count -gt 0) {
    $p0 += "Empty pages exist"
}

if (($pages | Where-Object {$_.state -eq "THIN"}).Count -gt 1) {
    $p1 += "Thin content pages"
}

$p0 = $p0 | Select-Object -First 3
$p1 = $p1 | Select-Object -First 3

$core = "Site lacks clear user flow and content depth"

# ===== REPORT =====

$r=@()
$r+="CORE PROBLEM:"
$r+=$core
$r+=""

$r+="P0:"
$p0 | ForEach-Object { $r+="- $_" }
$r+=""

$r+="P1:"
$p1 | ForEach-Object { $r+="- $_" }
$r+=""

$r+="VISUAL_LAYER: $(if ($VisualEnabled) {"ON"} else {"OFF"})"

$r+="DO NEXT:"
$r+="1. Add clear CTA"
$r+="2. Improve page depth"
$r+="3. Fix broken/empty pages"

# ===== SAVE =====

$r | Out-File (Join-Path $OutDir "REPORT.txt") -Encoding utf8
$pages | ConvertTo-Json -Depth 5 | Out-File (Join-Path $OutDir "page_type_audit.json")

Write-Output "AUDIT COMPLETE"

exit 0
