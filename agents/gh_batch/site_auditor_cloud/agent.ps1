# =========================
# CONFIG
# =========================

function Convert-ToStringArray {
    param($input)
    if (-not $input) { return @() }
    return @($input | ForEach-Object { [string]$_ })
}

function Save-Json {
    param($path, $data)
    $json = $data | ConvertTo-Json -Depth 10
    $json | Out-File -Encoding utf8 $path
}

function Ensure-ReportsDir {
    if (-not (Test-Path "reports")) {
        New-Item -ItemType Directory -Path "reports" | Out-Null
    }
    if (-not (Test-Path "reports/screenshots")) {
        New-Item -ItemType Directory -Path "reports/screenshots" | Out-Null
    }
}

# =========================
# ROUTE INVENTORY
# =========================

function Build-RouteInventory {
    param($BaseUrl)

    # Минимальный seed + расширение
    $routes = @(
        "/",
        "/hubs/",
        "/tools/",
        "/start-here/",
        "/search/"
    )

    # нормализация
    $routes = $routes | Select-Object -Unique

    $full = @()
    foreach ($r in $routes) {
        if ($r.StartsWith("http")) {
            $full += $r
        } else {
            $full += ($BaseUrl.TrimEnd("/") + $r)
        }
    }

    return $full
}

# =========================
# CORE ENTRY
# =========================

function Invoke-SiteAuditor {
    param(
        $BaseUrl
    )

    Ensure-ReportsDir

    Write-Host "BASE URL: $BaseUrl"

    # 1. ROUTES
    $routes = Build-RouteInventory -BaseUrl $BaseUrl
    Save-Json "reports/route_inventory.json" $routes

    # 2. CALL NODE CAPTURE
    $captureCmd = "node capture.mjs `"$BaseUrl`" reports/route_inventory.json reports"
    Write-Host "RUN: $captureCmd"

    cmd /c $captureCmd

    # 3. VERIFY OUTPUT
    $manifestExists = Test-Path "reports/visual_manifest.json"

    $status = "FAIL_VISUAL"
    if ($manifestExists) {
        $status = "PASS_V3_SCREENSHOT"
    }

    $summary = @{
        base_url = $BaseUrl
        route_count = $routes.Count
        visual_manifest = $manifestExists
        status = $status
    }

    Save-Json "reports/visual_summary.json" $summary

    return $summary
}
