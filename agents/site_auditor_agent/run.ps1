$AgentRoot = $PSScriptRoot
$RunLog = Join-Path $AgentRoot "RUN_INTERNAL_LOG.txt"
$ErrLog = Join-Path $AgentRoot "RUN_INTERNAL_ERROR.txt"

Remove-Item -LiteralPath $RunLog -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ErrLog -ErrorAction SilentlyContinue

function Write-RunLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -LiteralPath $RunLog -Append -Encoding utf8
}

try {
    if (!(Test-Path -LiteralPath (Join-Path $AgentRoot "agent.ps1"))) {
        throw "AGENT_SCRIPT_NOT_FOUND"
    }

    if (!(Test-Path -LiteralPath (Join-Path $AgentRoot "agent.config.json"))) {
        throw "CONFIG_NOT_FOUND"
    }

    if (!(Test-Path -LiteralPath (Join-Path $AgentRoot ".state\github_token.txt"))) {
        throw "TOKEN_FILE_NOT_FOUND"
    }

    Write-RunLog "START"
    . (Join-Path $AgentRoot "agent.ps1")
    Invoke-SiteAudit *>> $RunLog
    Write-RunLog "PASS"
    Write-Host ""
    Write-Host "PASS"
}
catch {
    $_ | Format-List * -Force | Out-File -LiteralPath $ErrLog -Encoding utf8
    Write-RunLog "FAIL"
    Write-Host ""
    Write-Host "FAIL"
    Write-Host "Open:"
    Write-Host $ErrLog
}
