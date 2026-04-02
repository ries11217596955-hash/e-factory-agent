function Build-RouteInventory {
    param($BaseUrl)

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

    # ROUTES
    $routes = Build-RouteInventory -BaseUrl $BaseUrl
    $routesPath = Join-Path $ReportsDir "route_inventory.json"
    Save-Json $routesPath $routes

    # NODE CAPTURE
    $nodeScript = Join-Path $PSScriptRoot "capture.mjs"

    Write-Host "RUN NODE CAPTURE"
    & node $nodeScript $BaseUrl $routesPath $ReportsDir

    if ($LASTEXITCODE -ne 0) {
        throw "Node capture failed"
    }

    # VERIFY
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
