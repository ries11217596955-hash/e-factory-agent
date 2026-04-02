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

function Invoke-SiteAuditor {
    param($BaseUrl)

    Write-Host "TEST FUNCTION LOADED"
}
