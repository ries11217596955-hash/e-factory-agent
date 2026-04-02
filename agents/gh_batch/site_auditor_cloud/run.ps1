[CmdletBinding()]
param(
  [string]$ReportsDir = "reports"
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentPath = Join-Path $scriptRoot 'agent.ps1'

Write-Host "=== PREFLIGHT ==="
Write-Host "scriptRoot: $scriptRoot"
Write-Host "agentPath: $agentPath"

if (-not (Test-Path $agentPath)) {
  throw "agent.ps1 NOT FOUND: $agentPath"
}

if (-not $env:GH_PAT) {
  throw "GH_PAT is EMPTY"
}

. $agentPath

# гарантируем папку reports ДО запуска
if (-not (Test-Path $ReportsDir)) {
  New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
}

try {
  $repoList = @(
    'ries11217596955-hash/automation-kb'
    'ries11217596955-hash/e-factory-agent'
    'ries11217596955-hash/e-factory-memory'
  )

  Invoke-SiteAuditor `
    -ReportsDir $ReportsDir `
    -RepoList $repoList `
    -Token $env:GH_PAT

  Write-Host "=== RUN PASS ==="
}
catch {
  Write-Host "=== RUN FAIL ==="
  Write-Host $_.Exception.Message

  # даже при падении пишем файл
  $fail = @{
    status = "FAIL_RUNTIME"
    error  = $_.Exception.Message
  }

  $fail | ConvertTo-Json -Depth 5 | Out-File "$ReportsDir\FAIL.json"

  throw
}
