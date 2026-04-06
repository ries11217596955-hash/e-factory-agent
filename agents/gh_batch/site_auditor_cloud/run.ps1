$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "PREFLIGHT"
Write-Host "scriptRoot: $scriptRoot"

$agentPath = Join-Path $scriptRoot "agent.ps1"
if (-not (Test-Path -LiteralPath $agentPath)) {
    throw "agent.ps1 not found at $agentPath"
}

Write-Host "LOADING AGENT: $agentPath"
. $agentPath

if (-not (Get-Command Invoke-SiteAuditor -ErrorAction SilentlyContinue)) {
    throw "Invoke-SiteAuditor NOT LOADED"
}

$BaseUrl = "https://automation-kb.pages.dev"
Write-Host "BASE URL: $BaseUrl"

$reportsDir = Join-Path $scriptRoot "reports"
if (Test-Path -LiteralPath $reportsDir) {
    Remove-Item -LiteralPath $reportsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

Push-Location $scriptRoot
try {
    Write-Host "RUN CAPTURE: node capture.mjs"
    & node capture.mjs
    if ($LASTEXITCODE -ne 0) {
        throw "capture.mjs failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$manifestPath = Join-Path $reportsDir "visual_manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "visual_manifest.json not created at $manifestPath"
}

Invoke-SiteAuditor -BaseUrl $BaseUrl

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$shotCount = 0
foreach($m in @($manifest)){ $shotCount += [int]$m.screenshotCount }

@"
MODE: LIVE_URL
BASE_URL: $BaseUrl
STATUS: PASS
SCREENSHOT_COUNT: $shotCount
REPORT: $(Join-Path $reportsDir 'REPORT.txt')
VISUAL_LAYER: ON
"@ | Set-Content -LiteralPath (Join-Path $reportsDir "RUN_REPORT.txt") -Encoding UTF8

Write-Host "AUDIT COMPLETE"
exit 0
