$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "PREFLIGHT"
Write-Host ("scriptRoot: " + $scriptRoot)

$agentPath = Join-Path $scriptRoot "agent.ps1"
if (-not (Test-Path $agentPath)) {
    throw "agent.ps1 not found: $agentPath"
}

. $agentPath

if (-not (Get-Command Build-RouteInventory -ErrorAction SilentlyContinue)) {
    throw "Build-RouteInventory NOT LOADED"
}
if (-not (Get-Command Invoke-SiteAuditor -ErrorAction SilentlyContinue)) {
    throw "Invoke-SiteAuditor NOT LOADED"
}

$baseUrl = $env:SITE_BASE_URL
if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    $baseUrl = "https://automation-kb.pages.dev"
}
Write-Host ("BASE URL: " + $baseUrl)

$node = "node"
Push-Location $scriptRoot
try {
    Write-Host "RUN CAPTURE: node capture.mjs"
    & $node "capture.mjs"
    if ($LASTEXITCODE -ne 0) {
        throw "capture.mjs failed with exit code $LASTEXITCODE"
    }

    $manifestPath = Join-Path $scriptRoot "reports/visual_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        throw "visual_manifest.json not found after capture: $manifestPath"
    }

    Write-Host "V6/V7 CAPTURE DONE"
    Invoke-SiteAuditor -BaseUrl $baseUrl
}
finally {
    Pop-Location
}
