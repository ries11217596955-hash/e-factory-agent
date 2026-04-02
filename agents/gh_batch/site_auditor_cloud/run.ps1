$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "PREFLIGHT"
Write-Host "scriptRoot: $scriptRoot"

$agentPath = Join-Path $scriptRoot "agent.ps1"

if (-not (Test-Path $agentPath)) {
    throw "agent.ps1 not found at $agentPath"
}

Write-Host "LOADING AGENT: $agentPath"

# ✅ ПРИНУДИТЕЛЬНАЯ ЗАГРУЗКА В СКОУП
. $agentPath

# ✅ ПРОВЕРКА ЧТО ФУНКЦИЯ ЕСТЬ
if (-not (Get-Command Build-RouteInventory -ErrorAction SilentlyContinue)) {
    throw "Build-RouteInventory NOT LOADED"
}

if (-not (Get-Command Invoke-SiteAuditor -ErrorAction SilentlyContinue)) {
    throw "Invoke-SiteAuditor NOT LOADED"
}

# SSOT target
$BaseUrl = "https://automation-kb.pages.dev"

Write-Host "BASE URL: $BaseUrl"

Invoke-SiteAuditor -BaseUrl $BaseUrl
