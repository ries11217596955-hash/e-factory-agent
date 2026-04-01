function Normalize-FrontMatterValue {
    param([string]$Value)

    if ($null -eq $Value) { return $null }
    $clean = $Value.Trim()
    $chars = [char[]]@("'", '"', ' ', "`t")
    $clean = $clean.Trim($chars)
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    return $clean
}

function Test-IsFalseyPermalinkValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $trimChars = [char[]]@("'", '"', ' ')
    $norm = $Value.Trim().Trim($trimChars).ToLowerInvariant()
    return @('false','null','none','off','0') -contains $norm
}

function Get-FrontMatterBlock {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    $normalized = $Content -replace "`r`n", "`n"
    if ($normalized -match '(?s)^---\n(.*?)\n---\n') {
        return $Matches[1]
    }
    return $null
}

function Get-FirstMarkdownHeading {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    $normalized = $Content -replace "`r`n", "`n"
    $normalized = [regex]::Replace($normalized, '(?s)^---\n.*?\n---\n', '')
    foreach ($line in ($normalized -split "`n")) {
        $trim = $line.Trim()
        if ($trim -match '^#\s+(.+)$') {
            return (Normalize-FrontMatterValue -Value $Matches[1])
        }
    }
    return $null
}

function Get-HtmlTitle {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    if ($Content -match '(?is)<title[^>]*>(.*?)</title>') {
        $v = $Matches[1] -replace '<[^>]+>', ' '
        return (Normalize-FrontMatterValue -Value $v)
    }
    if ($Content -match '(?is)<h1[^>]*>(.*?)</h1>') {
        $v = $Matches[1] -replace '<[^>]+>', ' '
        return (Normalize-FrontMatterValue -Value $v)
    }
    return $null
}

function Get-MetaDescription {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }

    if ($Content -match '(?is)<meta\s+name="description"\s+content="(.*?)"') {
        return (Normalize-FrontMatterValue -Value $Matches[1])
    }
    if ($Content -match "(?is)<meta\s+name='description'\s+content='(.*?)'") {
        return (Normalize-FrontMatterValue -Value $Matches[1])
    }
    if ($Content -match '(?is)<meta\s+content="(.*?)"\s+name="description"') {
        return (Normalize-FrontMatterValue -Value $Matches[1])
    }
    if ($Content -match "(?is)<meta\s+content='(.*?)'\s+name='description'") {
        return (Normalize-FrontMatterValue -Value $Matches[1])
    }
    return $null
}

function Get-FirstContentExcerpt {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    $normalized = $Content -replace "`r`n", "`n"
    $normalized = [regex]::Replace($normalized, '(?s)^---\n.*?\n---\n', '')
    $normalized = [regex]::Replace($normalized, '(?is)<script[^>]*>.*?</script>', ' ')
    $normalized = [regex]::Replace($normalized, '(?is)<style[^>]*>.*?</style>', ' ')
    $normalized = [regex]::Replace($normalized, '(?im)^#{1,6}\s+.+$', ' ')
    $normalized = [regex]::Replace($normalized, '(?im)^\s*[{%].*$', ' ')
    $normalized = [regex]::Replace($normalized, '(?im)^\s*[{][{].*$', ' ')
    $normalized = [regex]::Replace($normalized, '<[^>]+>', ' ')
    $normalized = [regex]::Replace($normalized, '\[[^\]]+\]\([^\)]+\)', ' ')
    $normalized = [regex]::Replace($normalized, '[*_`>#-]', ' ')

    $blocks = [regex]::Split($normalized, "`n`n+")
    foreach ($block in $blocks) {
        $text = [regex]::Replace($block, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.Length -lt 40) { continue }
        if ($text -match '^[\{\}\[\]%$]') { continue }
        if ($text.Length -gt 180) {
            $text = $text.Substring(0,180).Trim()
            if ($text -notmatch '[\.!?]$') { $text = $text.TrimEnd(',;:') + '…' }
        }
        return $text
    }
    return $null
}

function Get-TitleFromRoute {
    param([string]$Route)

    if ([string]::IsNullOrWhiteSpace($Route)) { return $null }
    $parts = @($Route.Trim('/') -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($parts).Count -eq 0) { return 'Home' }
    $last = $parts[-1] -replace '[-_]+', ' '
    if ([string]::IsNullOrWhiteSpace($last)) { return $null }
    return (Get-Culture).TextInfo.ToTitleCase($last)
}

function Get-RelativeRepoPath {
    param(
        [string]$RepoPath,
        [string]$FilePath
    )

    return $FilePath.Substring($RepoPath.Length).TrimStart([char]'\',[char]'/') -replace '\\','/'
}

function Convert-RepoPathToRoute {
    param(
        [string]$RepoPath,
        [string]$FilePath,
        [string]$BaseUrl
    )

    $relative = Get-RelativeRepoPath -RepoPath $RepoPath -FilePath $FilePath
    $normalized = $relative

    if ($normalized -match '^src/') {
        $normalized = $normalized.Substring(4)
    }

    $route = $normalized
    $route = $route -replace '/index\.(md|html|njk)$','/'
    $route = $route -replace '\.(md|html|njk)$','/'
    $route = $route -replace '/+','/'
    if (-not $route.StartsWith('/')) { $route = '/' + $route }
    if ($route -eq '/index/' -or $route -eq '/index') { $route = '/' }

    $isCanonicalAsset = ($route -match '^/(404\.html|search\.json|site\.webmanifest|sitemap\.xml)$') -or ($route -match '^/feeds/.+\.xml$')
    if ((-not $isCanonicalAsset) -and $route -ne '/' -and -not $route.EndsWith('/')) { $route = $route + '/' }

    $fullUrl = $BaseUrl.TrimEnd('/') + $route

    return [PSCustomObject]@{
        relative_path = $normalized
        route         = $route
        full_url      = $fullUrl
    }
}

function Get-ClusterIdFromPath {
    param([string]$RelativePath)

    $norm = $RelativePath.ToLowerInvariant()
    if ($norm -match '^src/posts/') { return 'posts' }
    if ($norm -match '^src/tools/') { return 'tools' }
    if ($norm -match '^src/hubs/news/' -or $norm -match '^src/news/') { return 'news' }
    return $null
}

function Get-PageType {
    param(
        [string]$Route,
        [string]$RelativePath
    )

    $norm = $RelativePath.ToLowerInvariant()
    $routeNorm = ''
    if ($Route) { $routeNorm = $Route.ToLowerInvariant() }

    if ($routeNorm -eq '/') { return 'home' }
    if ($routeNorm -match '^/404(\.html)?/?$') { return 'special_404' }
    if ($routeNorm -match '^/search\.json/?$') { return 'special_search' }
    if ($routeNorm -match '^/site\.webmanifest/?$') { return 'special_manifest' }
    if ($routeNorm -match '^/sitemap\.xml/?$') { return 'special_sitemap' }
    if ($routeNorm -match '^/feeds/.+\.xml/?$') { return 'special_feed' }

    if ($norm -match '^src/hubs/' -or $routeNorm -in @('/posts/','/tools/','/news/')) { return 'hub' }
    if ($norm -match '^src/posts/' -or $norm -match '^src/tools/' -or $norm -match '^src/news/') { return 'article' }

    return 'page'
}

function Test-IsServiceEndpointRoute {
    param([string]$Route)

    $routeNorm = $Route.ToLowerInvariant()
    if ($routeNorm -match '^/404\.html/?$') { return $true }
    if ($routeNorm -match '^/search\.json/?$') { return $true }
    if ($routeNorm -match '^/site\.webmanifest/?$') { return $true }
    if ($routeNorm -match '^/sitemap\.xml/?$') { return $true }
    if ($routeNorm -match '^/feeds/.+\.xml/?$') { return $true }
    return $false
}

function Test-IsPublishableCandidate {
    param(
        [string]$RelativePath,
        [object]$Config
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }

    $norm = "/" + $RelativePath.ToLowerInvariant()
    if (-not $norm.StartsWith("/src/")) { return $false }
    if ($norm -notmatch '\.(md|html|njk)$') { return $false }

    foreach ($pattern in @($Config.exclude_path_contains)) {
        if (-not [string]::IsNullOrWhiteSpace($pattern)) {
            $p = $pattern.ToLowerInvariant()
            if ($norm.Contains($p)) { return $false }
        }
    }

    if ($norm -match '/(_includes|layouts|partials|snippets|macros|shortcodes)/') { return $false }
    if ($norm -match '/(_data|data)/') { return $false }
    if ($norm -match '/(assets|images|img|css|js|fonts)/') { return $false }

    return $true
}

function Get-ContentRole {
    param(
        [string]$RelativePath,
        [bool]$IsPublishable,
        [bool]$IsServiceEndpoint
    )

    $norm = "/" + $RelativePath.ToLowerInvariant()

    if ($IsServiceEndpoint) { return 'service_or_special_page' }
    if ($IsPublishable) { return 'publishable_page' }
    if ($norm -match '/(_includes|layouts|partials|snippets|macros|shortcodes)/') { return 'layout_or_template' }
    if ($norm -match '/(_data|data)/') { return 'data_or_support' }
    if ($norm -match '/(governance|memory|docs)/') { return 'governance_or_memory' }
    return 'service_or_debug'
}

function Get-ExtractedLinks {
    param([string]$Content)

    $links = @()
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $patterns = @(
        'href\s*=\s*"([^"]+)"',
        "href\s*=\s*'([^']+)'",
        'src\s*=\s*"([^"]+)"',
        "src\s*=\s*'([^']+)'",
        'action\s*=\s*"([^"]+)"',
        "action\s*=\s*'([^']+)'",
        '\[[^\]]+\]\(([^\)]+)\)'
    )

    foreach ($pattern in $patterns) {
        foreach ($m in [regex]::Matches($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            if ($m.Groups.Count -gt 1) {
                $val = $m.Groups[1].Value.Trim()
                if ($val) { $links += $val }
            }
        }
    }

    return @($links | Select-Object -Unique)
}

function Build-SiteInventory {
    param(
        [string]$RepoPath,
        [string]$BaseUrl,
        [object]$Config
    )

    $files = Get-ChildItem -LiteralPath $RepoPath -Recurse -File | Where-Object {
        $_.Extension -in '.md','.html','.njk'
    }

    $inventory = @()

    foreach ($f in $files) {
        $content = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $frontMatter = Get-FrontMatterBlock -Content $content
        $relative = Get-RelativeRepoPath -RepoPath $RepoPath -FilePath $f.FullName
        $routeInfo = Convert-RepoPathToRoute -RepoPath $RepoPath -FilePath $f.FullName -BaseUrl $BaseUrl

        $permalink = $null
        if ($frontMatter -and $frontMatter -match '(?im)^permalink\s*:\s*(.+)$') {
            $permalink = Normalize-FrontMatterValue -Value $Matches[1]
        }

        $permalinkIsFalsey = Test-IsFalseyPermalinkValue -Value $permalink
        $isPublishable = Test-IsPublishableCandidate -RelativePath $relative -Config $Config

        $route = $routeInfo.route
        $fullUrl = $routeInfo.full_url
        if ($permalink -and -not $permalinkIsFalsey) {
            if ($permalink.StartsWith('/')) { $route = $permalink } else { $route = '/' + $permalink }
            if ($route -eq '/index/' -or $route -eq '/index') { $route = '/' }
            $isCanonicalAsset = ($route -match '^/(404\.html|search\.json|site\.webmanifest|sitemap\.xml)$') -or ($route -match '^/feeds/.+\.xml$')
            if ((-not $isCanonicalAsset) -and $route -ne '/' -and -not $route.EndsWith('/')) { $route = $route + '/' }
            $fullUrl = $BaseUrl.TrimEnd('/') + $route
        }

        # Deterministic publishable rule:
        # src/*.md|html|njk are publishable unless permalink is explicitly falsey or route is a service endpoint.
        if ($isPublishable) { $isPublishable = $true }
        if ($permalinkIsFalsey) { $isPublishable = $false }

        $isServiceEndpoint = $false
        if ($route) {
            $isServiceEndpoint = Test-IsServiceEndpointRoute -Route $route
            if ($isServiceEndpoint) {
                $isPublishable = $false
            }
        }

        $clusterId = Get-ClusterIdFromPath -RelativePath $relative
        $pageType = if ($route) { Get-PageType -Route $route -RelativePath $relative } else { 'disabled_template' }
        $contentRole = Get-ContentRole -RelativePath $relative -IsPublishable $isPublishable -IsServiceEndpoint $isServiceEndpoint

        $title = $null
        $description = $null
        $titleSource = $null
        $descriptionSource = $null

        if ($frontMatter -and $frontMatter -match '(?im)^title\s*:\s*(.+)$') {
            $title = Normalize-FrontMatterValue -Value $Matches[1]
            if ($title) { $titleSource = 'front_matter' }
        }
        if ($frontMatter -and $frontMatter -match '(?im)^description\s*:\s*(.+)$') {
            $description = Normalize-FrontMatterValue -Value $Matches[1]
            if ($description) { $descriptionSource = 'front_matter' }
        }
        if ($frontMatter -and $frontMatter -match '(?im)^excerpt\s*:\s*(.+)$' -and -not $description) {
            $description = Normalize-FrontMatterValue -Value $Matches[1]
            if ($description) { $descriptionSource = 'excerpt' }
        }
        if ($frontMatter -and $frontMatter -match '(?im)^summary\s*:\s*(.+)$' -and -not $description) {
            $description = Normalize-FrontMatterValue -Value $Matches[1]
            if ($description) { $descriptionSource = 'summary' }
        }

        if (-not $title -or $title -eq 'index') {
            $fallbackTitle = Get-FirstMarkdownHeading -Content $content
            if (-not $fallbackTitle) { $fallbackTitle = Get-HtmlTitle -Content $content }
            if (-not $fallbackTitle -or $fallbackTitle -eq 'index') { $fallbackTitle = Get-TitleFromRoute -Route $route }
            if ($fallbackTitle) {
                $title = $fallbackTitle
                if (-not $titleSource) { $titleSource = 'derived' }
            }
        }

        if (-not $description) {
            $fallbackDesc = Get-MetaDescription -Content $content
            if (-not $fallbackDesc) { $fallbackDesc = Get-FirstContentExcerpt -Content $content }
            if ($fallbackDesc) {
                $description = $fallbackDesc
                if (-not $descriptionSource) { $descriptionSource = 'derived' }
            }
        }

        $links = Get-ExtractedLinks -Content $content

        $inventory += [PSCustomObject]@{
            file               = $routeInfo.relative_path
            source_path        = $f.FullName
            title              = $title
            title_source       = $titleSource
            description        = $description
            description_source = $descriptionSource
            permalink          = $permalink
            permalink_falsey   = [bool]$permalinkIsFalsey
            route              = $route
            full_url           = $fullUrl
            links              = @($links)
            is_publishable     = [bool]$isPublishable
            content_role       = $contentRole
            cluster_id         = $clusterId
            page_type          = $pageType
        }
    }

    return $inventory
}