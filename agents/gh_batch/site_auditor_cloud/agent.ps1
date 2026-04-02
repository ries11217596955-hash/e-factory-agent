# =========================
# ROUTE INVENTORY
# =========================

function Build-RouteInventory {
    param($BaseUrl)

    if (-not $BaseUrl) {
        throw "BaseUrl is null"
    }

    $base = $BaseUrl.TrimEnd('/')

    $routes = @(
        '/',
        '/hubs/',
        '/tools/',
        '/start-here/',
        '/search/'
    )

    $full = @()

    foreach ($r in $routes) {
        $full += ($base + $r)
    }

    return $full
}

# =========================
# HELPERS
# =========================

function Save-Json {
    param($Path, $Data)

    $json = $Data | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $Path -Encoding utf8
}

function Ensure-Dir {
    param($Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# =========================
# NODE CAPTURE
# =========================

function Invoke-NodeCapture {
    param($BaseUrl, $RoutesPath, $ReportsDir)

    $nodeScript = Join-Path $PSScriptRoot "capture.mjs"

    if (-not (Test-Path $nodeScript)) {
        throw "capture.mjs not found"
    }

    Write-Host "RUN NODE CAPTURE"

    & node $nodeScript $BaseUrl $RoutesPath $ReportsDir

    if ($LASTEXITCODE -ne 0) {
        throw "Node capture failed"
    }
}

# =========================
# CORE
# =========================

function Invoke-SiteAuditor {
    param($BaseUrl)

    if (-not $BaseUrl) {
        throw "BaseUrl required"
    }

    $ReportsDir = Join-Path (Get-Location) "reports"
    $ScreensDir = Join-Path $ReportsDir "screenshots"

    Ensure-Dir $ReportsDir
    Ensure-Dir $ScreensDir

    Write-Host "BASE URL: $BaseUrl"

    $routes = Build-RouteInventory -BaseUrl $BaseUrl

    $routesPath = Join-Path $ReportsDir "route_inventory.json"
    Save-Json $routesPath $routes

    Invoke-NodeCapture $BaseUrl $routesPath $ReportsDir

    $manifestPath = Join-Path $ReportsDir "visual_manifest.json"

    if (-not (Test-Path $manifestPath)) {
        throw "visual_manifest.json missing"
    }

    $screens = Get-ChildItem $ScreensDir -Filter *.png -ErrorAction SilentlyContinue

    $status = "FAIL_VISUAL"

    if ($screens.Count -gt 0) {
        $status = "PASS_V3_SCREENSHOT"
    }

    $summary = @{
        base_url = $BaseUrl
        route_count = $routes.Count
        screenshots_count = $screens.Count
        status = $status
    }

    Save-Json (Join-Path $ReportsDir "visual_summary.json") $summary
    Save-Json (Join-Path $ReportsDir "final-status.json") @{ status = $status }

    return $summary
}
