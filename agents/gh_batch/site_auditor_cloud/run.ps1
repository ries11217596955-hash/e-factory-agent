$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

. "$scriptRoot/agent.ps1"

# SSOT target for cloud visual audit
$BaseUrl = "https://automation-kb.pages.dev"

Write-Host "PREFLIGHT"
Write-Host "scriptRoot: $scriptRoot"
Write-Host "agentPath: $scriptRoot/agent.ps1"
Write-Host "BASE URL: $BaseUrl"

Invoke-SiteAuditor -BaseUrl $BaseUrl
