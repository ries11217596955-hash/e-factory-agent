[CmdletBinding()]
param(
  [string]$ReportsDir = "reports"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentPath = Join-Path $scriptRoot 'agent.ps1'

if (-not (Test-Path $agentPath)) {
  throw "agent.ps1 not found: $agentPath"
}

. $agentPath

$repoList = @(
  'ries11217596955-hash/automation-kb'
  'ries11217596955-hash/e-factory-agent'
  'ries11217596955-hash/e-factory-memory'
)

$token = $env:GH_PAT

Invoke-SiteAuditor `
  -ReportsDir $ReportsDir `
  -RepoList $repoList `
  -Token $token
