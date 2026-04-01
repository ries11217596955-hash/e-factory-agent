$AgentRoot = $PSScriptRoot
$ShortcutName = "SITE_AUDITOR_AGENT.lnk"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopPath $ShortcutName
$PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$RunScript = Join-Path $AgentRoot "run.ps1"

if (!(Test-Path -LiteralPath $RunScript)) {
    throw "RUN_SCRIPT_NOT_FOUND: $RunScript"
}

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $PowerShellExe
$Shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $RunScript + '"'
$Shortcut.WorkingDirectory = $AgentRoot
$Shortcut.IconLocation = $PowerShellExe + ",0"
$Shortcut.Description = "SITE_AUDITOR_AGENT"
$Shortcut.Save()

Write-Host "SHORTCUT_CREATED:"
Write-Host $ShortcutPath
