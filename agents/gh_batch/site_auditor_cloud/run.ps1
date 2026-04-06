param()

$ErrorActionPreference = "Stop"

$RunId = (Get-Date -Format "yyyyMMdd_HHmmss")
$Root = "$PSScriptRoot"
$OutDir = Join-Path $Root "outbox\$RunId"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ZipPath = Join-Path $Root "input\site.zip"
$Target = Join-Path $Root "target_repo"

# ---------- ZIP MODE ----------

if (Test-Path $ZipPath) {

    Write-Output "ZIP MODE DETECTED"

    $Extract = Join-Path $Root "zip_extract"
    if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }

    Expand-Archive -Path $ZipPath -DestinationPath $Extract -Force

    $sub = Get-ChildItem $Extract

    if ($sub.Count -eq 1 -and $sub[0].PSIsContainer) {
        $Target = $sub[0].FullName
    } else {
        $Target = $Extract
    }

} else {

    Write-Output "REPO MODE"

    if (!(Test-Path $Target)) {
        Write-Error "target_repo not found"
        exit 1
    }
}

# ---------- RUN CORE ----------

$Agent = Join-Path $Root "agent.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass `
    -File $Agent `
    -TargetPath $Target `
    -OutDir $OutDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "agent failed"
    exit 1
}

"DONE.ok" | Out-File (Join-Path $OutDir "DONE.ok")

@"
RUN_ID: $RunId
STATUS: PASS
MODE: $(if (Test-Path $ZipPath) {"ZIP"} else {"REPO"})
"@ | Out-File (Join-Path $OutDir "RUN_REPORT.txt")

Write-Output "DONE: $OutDir"
