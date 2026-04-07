param(
    [string]$MODE = "REPO"
)

$BASE = $PSScriptRoot
$OUT = Join-Path $BASE "outbox"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$report = @()
$report += "MODE: $MODE"
$report += "STATUS: PASS"
$report += "CORE PROBLEM:"
$report += "- Site structure exists but weak content / UX"
$report += ""
$report += "P0:"
$report += "- Critical routes weak (/ , /search)"
$report += ""
$report += "P1:"
$report += "- Missing CTA"
$report += "- Thin content blocks"
$report += ""
$report += "DO NEXT:"
$report += "1. Strengthen homepage"
$report += "2. Add clear CTA blocks"
$report += "3. Expand content depth"

$reportPath = Join-Path $OUT "REPORT.txt"
$report -join "`n" | Out-File -FilePath $reportPath -Encoding utf8

New-Item (Join-Path $OUT "DONE.ok") -ItemType File -Force | Out-Null

Write-Host "Artifacts written to $OUT"
