
function Test-IsTemplateExpressionLink {
    param([string]$Link)

    if ([string]::IsNullOrWhiteSpace($Link)) { return $false }
    if ($Link -match '\{\{.+\}\}') { return $true }
    if ($Link -match '\{%.*%\}') { return $true }
    if ($Link -match '\+esc\(.+\)\+') { return $true }
    if ($Link -match '\$\{.+\}') { return $true }
    return $false
}

function Resolve-InventoryLinkRoute {
    param(
        [string]$Link,
        [string]$CurrentRoute
    )

    if ([string]::IsNullOrWhiteSpace($Link)) { return $null }
    if ($Link -match '^(http|https|mailto|tel):') { return $null }
    if ($Link.StartsWith('#')) { return $CurrentRoute }

    $linkOnly = $Link.Split('#')[0].Split('?')[0]
    if ([string]::IsNullOrWhiteSpace($linkOnly)) { return $CurrentRoute }

    if ($linkOnly.StartsWith('/')) {
        $route = $linkOnly
    }
    else {
        $base = $CurrentRoute
        if (-not $base.EndsWith('/')) { $base = $base + '/' }
        $route = $base + $linkOnly
    }

    $route = $route -replace '/+','/'
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($route -split '/')) {
        if ($part -eq '' -or $part -eq '.') { continue }
        if ($part -eq '..') {
            if ($parts.Count -gt 0) { $parts.RemoveAt($parts.Count - 1) }
            continue
        }
        $parts.Add($part)
    }

    $normalized = '/' + (($parts -join '/').Trim('/'))
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq '/') { return '/' }
    $isCanonicalAsset = ($normalized -match '^/(404\.html|search\.json|site\.webmanifest|sitemap\.xml)$') -or ($normalized -match '^/feeds/.+\.xml$')
    if ($isCanonicalAsset) { return $normalized }
    return $normalized + '/'
}

function Get-BrokenLinkClassification {
    param(
        [string]$Link,
        [string]$TargetRoute,
        [hashtable]$RouteMap,
        [string]$CurrentRoute
    )

    if (Test-IsTemplateExpressionLink -Link $Link) {
        return [PSCustomObject]@{ kind='TEMPLATE_EXPRESSION_NOT_RENDERED'; likely_fix='ignore template expression or verify render'; severity='P3' }
    }

    if ($Link -match '^\./.+\.(md|njk|html)$') {
        return [PSCustomObject]@{ kind='RELATIVE_LINK_ON_PERMALINK_PAGE'; likely_fix='update source link to rendered route'; severity='P2' }
    }

    if ($TargetRoute -match '^/(404\.html|search\.json|site\.webmanifest|sitemap\.xml)/$' -or $TargetRoute -match '^/feeds/.+\.xml/$') {
        return [PSCustomObject]@{ kind='NON_DIRECTORY_ASSET_SLASH_ERROR'; likely_fix='normalize asset route'; severity='P2' }
    }

    $aliasCandidate = $TargetRoute.TrimEnd('/')
    if ($aliasCandidate -and $RouteMap.ContainsKey($aliasCandidate)) {
        return [PSCustomObject]@{ kind='NON_DIRECTORY_ASSET_SLASH_ERROR'; likely_fix='normalize route slash'; severity='P2' }
    }

    return [PSCustomObject]@{ kind='MISSING_TARGET_ROUTE'; likely_fix='update source link or add target route'; severity='P1' }
}

function Invoke-LinksAudit {
    param($Inventory)

    $pages = @($Inventory | Where-Object { $_.is_publishable -and -not [string]::IsNullOrWhiteSpace($_.route) })
    $routeMap = @{}
    foreach ($item in $pages) {
        $routeMap[$item.route] = $item
    }

    $incoming = @{}
    $navEdges = @()
    foreach ($item in $pages) {
        $incoming[$item.route] = 0
    }

    $broken = @()

    foreach ($item in $pages) {
        foreach ($lnk in @($item.links)) {
            if (Test-IsTemplateExpressionLink -Link $lnk) {
                $class = Get-BrokenLinkClassification -Link $lnk -TargetRoute $null -RouteMap $routeMap -CurrentRoute $item.route
                $broken += [PSCustomObject]@{
                    source_file    = $item.file
                    source_route   = $item.route
                    bad_link       = $lnk
                    target_route   = $null
                    issue_type     = $class.kind
                    likely_fix     = $class.likely_fix
                    severity       = $class.severity
                }
                continue
            }

            $targetRoute = Resolve-InventoryLinkRoute -Link $lnk -CurrentRoute $item.route
            if (-not $targetRoute) { continue }

            if ($routeMap.ContainsKey($targetRoute)) {
                $incoming[$targetRoute] = [int]$incoming[$targetRoute] + 1
                $navEdges += [PSCustomObject]@{
                    source_route = $item.route
                    target_route = $targetRoute
                }
            }
            else {
                $class = Get-BrokenLinkClassification -Link $lnk -TargetRoute $targetRoute -RouteMap $routeMap -CurrentRoute $item.route
                $broken += [PSCustomObject]@{
                    source_file    = $item.file
                    source_route   = $item.route
                    bad_link       = $lnk
                    target_route   = $targetRoute
                    issue_type     = $class.kind
                    likely_fix     = $class.likely_fix
                    severity       = $class.severity
                }
            }
        }
    }

    $orphans = @()
    foreach ($item in $pages) {
        if ($item.route -eq '/') { continue }
        if ([int]$incoming[$item.route] -eq 0) {
            $orphans += [PSCustomObject]@{
                file       = $item.file
                route      = $item.route
                severity   = 'P2'
                likely_fix = 'add internal links from hub, nav, or parent page'
            }
        }
    }

    $navGraph = foreach ($item in $pages) {
        $outgoing = @($navEdges | Where-Object { $_.source_route -eq $item.route }).Count
        [PSCustomObject]@{
            route          = $item.route
            page_type      = $item.page_type
            cluster_id     = $item.cluster_id
            incoming_count = [int]$incoming[$item.route]
            outgoing_count = $outgoing
        }
    }

    return [PSCustomObject]@{
        BrokenLinks = $broken
        Orphans     = $orphans
        NavGraph    = $navGraph
    }
}
