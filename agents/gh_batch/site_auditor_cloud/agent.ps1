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

function Normalize-FileNamePart {
    param($Text)

    if (-not $Text) { return "root" }

    $safe = $Text -replace '^https?://', ''
    $safe = $safe -replace '[^a-zA-Z0-9\-_\/]+', '_'
    $safe = $safe -replace '[\/]+', '__'
    $safe = $safe.Trim('_')

    if (-not $safe) { $safe = "root" }
    return $safe
}

# =========================
# ROUTES
# =========================

function Build-RouteInventory {
    param($BaseUrl)

    if (-not $BaseUrl) {
        throw "BaseUrl is null or empty"
    }

    $base = $BaseUrl.TrimEnd('/')

    $routes = @(
        '/',
        '/hubs/',
        '/tools/',
        '/start-here/',
        '/search/'
    ) | Select-Object -Unique

    $full = @()

    foreach ($r in $routes) {
        $full += ($base + $r)
    }

    return $full
}

# =========================
# VISUAL CAPTURE
# =========================

function Invoke-NodeCapture {
    param(
        $BaseUrl,
        $RouteInventoryPath,
        $ReportsDir
    )

    $nodeScript = Join-Path $PSScriptRoot "capture.mjs"

    if (-not (Test-Path $nodeScript)) {
        throw "capture.mjs not found: $nodeScript"
    }

    $args = @(
        $nodeScript
        $BaseUrl
        $RouteInventoryPath
        $ReportsDir
    )

    Write-Host "RUN NODE CAPTURE"
    Write-Host "node $($args -join ' ')"

    & node @args

    if ($LASTEXITCODE -ne 0) {
        throw "Node capture failed with exit code $LASTEXITCODE"
    }
}

# =========================
# CORE
# =========================

function Invoke-SiteAuditor {
    param(
        $BaseUrl
    )

    if (-not $BaseUrl) {
        throw "Invoke-SiteAuditor requires BaseUrl"
    }

    $ReportsDir = Join-Path (Get-Location) "reports"
    $ScreensDir = Join-Path $ReportsDir "screenshots"

    Ensure-Dir $ReportsDir
    Ensure-Dir $ScreensDir

    Write-Host "BASE URL: $BaseUrl"

    $routes = Build-RouteInventory -BaseUrl $BaseUrl
    Save-Json -Path (Join-Path $ReportsDir "route_inventory.json") -Data $routes

    Invoke-NodeCapture `
        -BaseUrl $BaseUrl `
        -RouteInventoryPath (Join-Path $ReportsDir "route_inventory.json") `
        -ReportsDir $ReportsDir

    $manifestPath = Join-Path $ReportsDir "visual_manifest.json"
    $summaryPath  = Join-Path $ReportsDir "visual_summary.json"
    $reportPath   = Join-Path $ReportsDir "REPORT.txt"
    $statusPath   = Join-Path $ReportsDir "final-status.json"

    $manifestExists = Test-Path $manifestPath
    $screenshots = @()

    if (Test-Path $ScreensDir) {
        $screenshots = Get-ChildItem -Path $ScreensDir -File -Filter *.png -ErrorAction SilentlyContinue
    }

    $status = "FAIL_VISUAL"

    if ($manifestExists -and $screenshots.Count -gt 0) {
        $status = "PASS_V3_SCREENSHOT"
    }

    $summary = @{
        base_url = $BaseUrl
        route_count = @($routes).Count
        screenshots_count = @($screenshots).Count
        visual_manifest = $manifestExists
        status = $status
    }

    Save-Json -Path $summaryPath -Data $summary
    Save-Json -Path $statusPath -Data @{ status = $status }

    @(
        "SITE AUDITOR VISUAL REPORT"
        "BASE URL: $BaseUrl"
        "ROUTES: $(@($routes).Count)"
        "SCREENSHOTS: $(@($screenshots).Count)"
        "STATUS: $status"
    ) | Out-File -FilePath $reportPath -Encoding utf8

    return $summary
}
