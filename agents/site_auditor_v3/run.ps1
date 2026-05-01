param(
    [string]$Mode = "LINK",
    [string]$BaseUrl = ""
)

Write-Host "V3: START"

$root = $PSScriptRoot
$registryPath = Join-Path $root "contracts/module_registry.json"

if (-not (Test-Path $registryPath)) {
    Write-Error "MODULE_REGISTRY_NOT_FOUND"
    exit 1
}

$registry = Get-Content $registryPath -Raw | ConvertFrom-Json

$pipeline = @{}

foreach ($m in $registry.modules) {
    if ($m.enabled -ne $true) { continue }

    $moduleFullPath = Join-Path $root ($m.path -replace "agents/site_auditor_v3/", "")

    if (-not (Test-Path $moduleFullPath)) {
        Write-Host "V3: SKIP (not found) $($m.id)"
        continue
    }

    . $moduleFullPath

    if ($m.id -eq "01_input") {
        $pipeline["input"] = Invoke-InputModule -BaseUrl $BaseUrl
    }

    if ($m.id -eq "02_route_audit") {
        $pipeline["route_audit"] = Invoke-RouteAuditModule -InputData $pipeline["input"]
    }
}

Write-Host "V3: PIPELINE STATE"
$pipeline | ConvertTo-Json -Depth 5

Write-Host "V3: END"
