
param([string]$ZipPath)

if (!(Test-Path $ZipPath)) {
    Write-Error "ZIP NOT FOUND"
    exit 1
}

Write-Output "PREFLIGHT OK"
