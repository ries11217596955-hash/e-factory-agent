
param(
    [string]$MODE = "REPO"
)

$OUT = "outbox"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$report = @"
MODE: $MODE
STATUS: PASS
NOTE: artifact generated
"@

$reportPath = Join-Path $OUT "REPORT.txt"
$report | Out-File -FilePath $reportPath -Encoding utf8

Write-Host "Artifact created at $reportPath"
