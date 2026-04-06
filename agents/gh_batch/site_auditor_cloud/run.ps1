param(
    [string]$ForceMode = "",
    [string]$BaseUrl = ""
)
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Inbox = Join-Path $Root "input\inbox"
$Processing = Join-Path $Root "input\processing"
$Done = Join-Path $Root "input\done"
$Failed = Join-Path $Root "input\failed"
New-Item -ItemType Directory -Force -Path $Processing,$Done,$Failed | Out-Null
function Move-Safe {
    param($src, $dst)
    try {
        Move-Item -Path $src -Destination $dst -Force
    } catch {
        $name = [IO.Path]::GetFileNameWithoutExtension($src)
        $ext = [IO.Path]::GetExtension($src)
        $dst2 = Join-Path (Split-Path $dst) "$name`_$(Get-Date -Format yyyyMMddHHmmss)$ext"
        Move-Item -Path $src -Destination $dst2 -Force
    }
}
$Mode = $ForceMode
if (-not $Mode) {
    $zip = Get-ChildItem $Inbox -Filter *.zip | Select-Object -First 1
    if ($zip) { $Mode = "ZIP" } else { $Mode = "REPO" }
}
Write-Host "MODE: $Mode"
# ================= ZIP =================
if ($Mode -eq "ZIP") {
    $zip = Get-ChildItem $Inbox -Filter *.zip | Select-Object -First 1
    if (-not $zip) { Write-Error "No ZIP"; exit 1 }
    $procZip = Join-Path $Processing $zip.Name
    Move-Safe $zip.FullName $procZip
    $tmp = Join-Path $Root "tmp_zip"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $procZip -DestinationPath $tmp -Force
    $sub = Get-ChildItem $tmp | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if ($sub) { $AuditRoot = $sub.FullName } else { $AuditRoot = $tmp }
    Write-Host "AUDIT ROOT: $AuditRoot"
    try {
        $global:LASTEXITCODE = 0
        & "$Root\agent.ps1" -Mode "ZIP" -TargetPath $AuditRoot
        if ($LASTEXITCODE -ne 0) { throw "agent fail" }
        Move-Safe $procZip (Join-Path $Done ([IO.Path]::GetFileName($procZip)))
        Write-Host "ZIP ROUTED: DONE"
        exit 0
    }
    catch {
        Move-Safe $procZip (Join-Path $Failed ([IO.Path]::GetFileName($procZip)))
        Write-Host "ZIP ROUTED: FAILED"
        exit 1
    }
}
# ================= REPO =================
if ($Mode -eq "REPO") {
    $repo = Join-Path $Root "target_repo"
    Write-Host "AUDIT ROOT: $repo"
    & "$Root\agent.ps1" -Mode "REPO" -TargetPath $repo
    exit $LASTEXITCODE
}
# ================= URL =================
if ($Mode -eq "URL") {
    if (-not $BaseUrl) {
        Write-Error "BASE_URL required"
        exit 1
    }
    Write-Host "URL TARGET: $BaseUrl"
    $env:BASE_URL = $BaseUrl
    & "$Root\agent.ps1" -Mode "URL" -TargetPath ""
    exit $LASTEXITCODE
}
