function Invoke-SiteAuditor {
    param(
        $BaseUrl
    )

    if (-not $BaseUrl) {
        throw "BaseUrl required"
    }

    $ReportsDir = Join-Path (Get-Location) "reports"
    $ScreensDir = Join-Path $ReportsDir "screenshots"

    # ✅ ВСЕГДА создаём заранее
    New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $ScreensDir -Force | Out-Null

    Write-Host "BASE URL: $BaseUrl"

    $routes = Build-RouteInventory -BaseUrl $BaseUrl

    Save-Json "$ReportsDir/route_inventory.json" $routes

    # ✅ ПРАВИЛЬНЫЙ запуск node
    $nodeScript = Join-Path $PSScriptRoot "capture.mjs"

    Write-Host "RUN NODE CAPTURE"
    & node $nodeScript $BaseUrl "$ReportsDir/route_inventory.json" $ReportsDir

    if ($LASTEXITCODE -ne 0) {
        throw "Node capture failed"
    }

    # ✅ проверяем результат
    $manifestPath = "$ReportsDir/visual_manifest.json"

    if (-not (Test-Path $manifestPath)) {
        throw "visual_manifest.json not created"
    }

    $screens = Get-ChildItem "$ScreensDir" -Filter *.png -ErrorAction SilentlyContinue

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

    Save-Json "$ReportsDir/visual_summary.json" $summary
    Save-Json "$ReportsDir/final-status.json" @{ status = $status }

    return $summary
}
