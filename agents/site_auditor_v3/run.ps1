param(
    [string]$Mode = "LINK",
    [string]$BaseUrl = ""
)

Write-Host "V3: START"

$root = $PSScriptRoot
$contractsPath = Join-Path $root "contracts/module_registry.json"

if (-not (Test-Path $contractsPath)) {
    Write-Error "MODULE_REGISTRY_NOT_FOUND"
    exit 1
}

$registry = Get-Content $contractsPath -Raw | ConvertFrom-Json

Write-Host "V3: MODULE COUNT = $($registry.modules.Count)"

foreach ($m in $registry.modules) {
    if ($m.enabled -ne $true) { continue }

    Write-Host "V3: MODULE -> $($m.id)"

    if (-not (Test-Path $m.path)) {
        Write-Host "V3: SKIP (module not implemented)"
        continue
    }

    . $m.path
}

Write-Host "V3: END"
