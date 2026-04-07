param([string]$MODE="REPO")
Write-Host "MODE:" $MODE
powershell -ExecutionPolicy Bypass -File agent.ps1 -MODE $MODE
