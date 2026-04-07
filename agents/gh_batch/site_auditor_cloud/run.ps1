param(
    [string]$MODE = "REPO"
)

Write-Host "MODE:" $MODE

if ($MODE -eq "REPO") {
    Write-Host "Running REPO audit"
}
elseif ($MODE -eq "ZIP") {
    Write-Host "Running ZIP audit"
}
elseif ($MODE -eq "URL") {
    Write-Host "Running URL audit"
}
else {
    Write-Host "Unknown mode"
    exit 1
}
