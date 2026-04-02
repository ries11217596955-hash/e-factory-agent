Set-StrictMode -Version Latest

function Save-JsonFile {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Object
  )

  $dir = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  try {
    $json = $Object | ConvertTo-Json -Depth 20
  }
  catch {
    $fallback = [ordered]@{
      error   = 'JSON_SERIALIZATION_FAILED'
      message = [string]$_.Exception.Message
      path    = $Path
    }
    $json = $fallback | ConvertTo-Json -Depth 5
  }

  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Save-TextFile {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $dir = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Get-PreviewText {
  param(
    [AllowNull()][object]$Value,
    [int]$MaxLength = 4000
  )

  if ($null -eq $Value) { return $null }

  $text = ''
  if ($Value -is [string]) {
    $text = $Value
  }
  else {
    try {
      $text = $Value | ConvertTo-Json -Depth 20 -Compress
    }
    catch {
      $text = [string]$Value
    }
  }

  if ($text.Length -gt $MaxLength) {
    return $text.Substring(0, $MaxLength)
  }

  return $text
}


function Convert-ToStringArray {
  param(
    [AllowNull()]$InputObject
  )

  if ($null -eq $InputObject) { return @() }

  $items = @($InputObject)
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($item in $items) {
    if ($null -eq $item) { continue }
    $result.Add([string]$item) | Out-Null
  }

  return @($result)
}

function Normalize-TreeItems {
  param(
    [AllowNull()]$TreeItems
  )

  if ($null -eq $TreeItems) { return @() }

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($item in @($TreeItems)) {
    if ($null -eq $item) { continue }

    $path = ''
    $type = ''
    try { $path = [string]$item.path } catch { $path = '' }
    try { $type = [string]$item.type } catch { $type = '' }

    $result.Add([pscustomobject]@{
      path = $path
      type = $type
      raw  = $item
    }) | Out-Null
  }

  return @($result)
}

function Invoke-GitHubApi {
  param(
    [Parameter(Mandatory=$true)][string]$Method,
    [Parameter(Mandatory=$true)][string]$Url,
    [string]$Token = '',
    [switch]$RawText
  )

  $headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'SITE_AUDITOR_AGENT'
    'X-GitHub-Api-Version' = '2022-11-28'
  }

  if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $headers['Authorization'] = "Bearer $Token"
  }

  try {
    $response = Invoke-WebRequest -Method $Method -Uri $Url -Headers $headers -MaximumRedirection 0 -ErrorAction Stop
    $bodyText = $response.Content
    $bodyJson = $null

    if (-not $RawText) {
      try {
        if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
          $bodyJson = $bodyText | ConvertFrom-Json
        }
      }
      catch {
        $bodyJson = $null
      }
    }

    $headerMap = @{}
    foreach ($key in $response.Headers.Keys) {
      $headerMap[$key] = [string]$response.Headers[$key]
    }

    return [pscustomobject]@{
      ok             = $true
      status_code    = [int]$response.StatusCode
      status_text    = [string]$response.StatusDescription
      url            = $Url
      method         = $Method
      headers        = $headerMap
      body_text      = $bodyText
      body_json      = $bodyJson
      error_message  = $null
      exception_type = $null
    }
  }
  catch {
    $ex = $_.Exception
    $statusCode = $null
    $statusText = $null
    $bodyText = $null
    $headerMap = @{}

    if ($ex.Response) {
      try { $statusCode = [int]$ex.Response.StatusCode } catch {}
      try { $statusText = [string]$ex.Response.StatusDescription } catch {}

      try {
        foreach ($key in $ex.Response.Headers.Keys) {
          $headerMap[$key] = [string]$ex.Response.Headers[$key]
        }
      } catch {}

      try {
        $stream = $ex.Response.GetResponseStream()
        if ($stream) {
          $reader = New-Object System.IO.StreamReader($stream)
          $bodyText = $reader.ReadToEnd()
          $reader.Close()
        }
      } catch {}
    }

    return [pscustomobject]@{
      ok             = $false
      status_code    = $statusCode
      status_text    = $statusText
      url            = $Url
      method         = $Method
      headers        = $headerMap
      body_text      = $bodyText
      body_json      = $null
      error_message  = [string]$ex.Message
      exception_type = $ex.GetType().FullName
    }
  }
}

function Write-StepTrace {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][string]$StepName,
    [Parameter(Mandatory=$true)]$Result,
    [hashtable]$Extra = @{}
  )

  $obj = [ordered]@{
    timestamp       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    repo            = $Repo
    step_name       = $StepName
    ok              = $Result.ok
    status_code     = $Result.status_code
    status_text     = $Result.status_text
    method          = $Result.method
    url             = $Result.url
    error_message   = $Result.error_message
    exception_type  = $Result.exception_type
    headers_preview = $Result.headers
    body_preview    = Get-PreviewText -Value $Result.body_text -MaxLength 4000
  }

  foreach ($k in $Extra.Keys) {
    $obj[$k] = $Extra[$k]
  }

  Save-JsonFile -Path $Path -Object $obj
}

function Get-RepoInventoryStats {
  param(
    $TreeItems
  )

  $items = @(Normalize-TreeItems -TreeItems $TreeItems)
  $blobItems = @($items | Where-Object { $_.type -eq 'blob' })

  $stats = [ordered]@{
    inventory_count = $blobItems.Count
    md_files        = 0
    html_files      = 0
    njk_files       = 0
    js_files        = 0
    css_files       = 0
    json_files      = 0
    image_files     = 0
    src_files       = 0
    hub_files       = 0
    root_files      = 0
  }

  foreach ($item in $blobItems) {
    $path = [string]$item.path
    $lower = $path.ToLowerInvariant()

    if ($lower.EndsWith('.md'))   { $stats.md_files++ }
    if ($lower.EndsWith('.html')) { $stats.html_files++ }
    if ($lower.EndsWith('.njk'))  { $stats.njk_files++ }
    if ($lower.EndsWith('.js'))   { $stats.js_files++ }
    if ($lower.EndsWith('.css'))  { $stats.css_files++ }
    if ($lower.EndsWith('.json')) { $stats.json_files++ }

    if (
      $lower.EndsWith('.png')  -or
      $lower.EndsWith('.jpg')  -or
      $lower.EndsWith('.jpeg') -or
      $lower.EndsWith('.webp') -or
      $lower.EndsWith('.gif')  -or
      $lower.EndsWith('.svg')
    ) {
      $stats.image_files++
    }

    if ($lower.StartsWith('src/')) {
      $stats.src_files++
    }

    if ($lower.StartsWith('src/hubs/')) {
      $stats.hub_files++
    }

    if ($path -notmatch '/') {
      $stats.root_files++
    }
  }

  return [pscustomobject]$stats
}

function Get-PagePaths {
  param(
    $TreeItems
  )

  $items = @(Normalize-TreeItems -TreeItems $TreeItems)
  $blobPaths = @($items | Where-Object { $_.type -eq 'blob' } | ForEach-Object { [string]$_.path })

  $pages = @(
    $blobPaths | Where-Object {
      $_.StartsWith('src/') -and
      -not $_.StartsWith('src/assets/') -and
      -not $_.StartsWith('src/_includes/') -and
      -not $_.StartsWith('src/_data/') -and
      -not $_.StartsWith('src/css/') -and
      -not $_.StartsWith('src/js/') -and
      -not $_.StartsWith('src/img/') -and
      -not $_.StartsWith('src/images/') -and
      (
        $_.ToLowerInvariant().EndsWith('.md') -or
        $_.ToLowerInvariant().EndsWith('.njk') -or
        $_.ToLowerInvariant().EndsWith('.html')
      )
    }
  )

  return @($pages | Sort-Object -Unique | ForEach-Object { [string]$_ })
}

function Convert-PagePathToRoute {
  param(
    [Parameter(Mandatory=$true)][string]$Path
  )

  $route = $Path

  if ($route.StartsWith('src/')) {
    $route = $route.Substring(4)
  }

  $lower = $route.ToLowerInvariant()

  if ($lower -eq 'index.md' -or $lower -eq 'index.njk' -or $lower -eq 'index.html') {
    return '/'
  }

  $route = $route -replace '\.md$',''
  $route = $route -replace '\.njk$',''
  $route = $route -replace '\.html$',''

  if ($route.EndsWith('/index')) {
    $route = $route.Substring(0, $route.Length - '/index'.Length)
  }

  if ([string]::IsNullOrWhiteSpace($route)) {
    return '/'
  }

  if (-not $route.StartsWith('/')) {
    $route = "/$route"
  }

  return $route
}

function Get-RouteDepth {
  param(
    [Parameter(Mandatory=$true)][string]$Route
  )

  if ($Route -eq '/') { return 0 }

  $trimmed = $Route.Trim('/')
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return 0 }

  return @($trimmed.Split('/')).Count
}

function Get-DirectoryList {
  param(
    $TreeItems
  )

  $items = @(Normalize-TreeItems -TreeItems $TreeItems)
  $dirs = @($items | Where-Object { $_.type -eq 'tree' } | ForEach-Object { [string]$_.path })
  return @($dirs | Sort-Object -Unique | ForEach-Object { [string]$_ })
}

function Get-EmptyDirectories {
  param(
    $TreeItems
  )

  $items = @(Normalize-TreeItems -TreeItems $TreeItems)
  $dirs = @(Get-DirectoryList -TreeItems $items)
  $allPaths = @($items | ForEach-Object { [string]$_.path })

  $empty = New-Object System.Collections.Generic.List[string]
  foreach ($dir in $dirs) {
    $prefix = "$dir/"
    $children = @($allPaths | Where-Object { $_ -ne $dir -and $_.StartsWith($prefix) })
    if ($children.Count -eq 0) {
      $empty.Add([string]$dir) | Out-Null
    }
  }

  return @($empty | Sort-Object -Unique | ForEach-Object { [string]$_ })
}

function Get-HubMap {
  param(
    $PagePaths
  )

  $normalized = @(Convert-ToStringArray -InputObject $PagePaths)

  $hubBuckets = @{}

  foreach ($path in $normalized) {
    if ($path.StartsWith('src/hubs/')) {
      $rest = $path.Substring('src/hubs/'.Length)
      $parts = @($rest.Split('/'))
      if ($parts.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
        $hub = [string]$parts[0]
        if (-not $hubBuckets.ContainsKey($hub)) {
          $hubBuckets[$hub] = New-Object System.Collections.Generic.List[string]
        }
        $hubBuckets[$hub].Add([string]$path) | Out-Null
      }
    }
  }

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($hub in ($hubBuckets.Keys | Sort-Object)) {
    $pages = @($hubBuckets[$hub] | Sort-Object -Unique | ForEach-Object { [string]$_ })
    $result.Add([pscustomobject]@{
      hub        = [string]$hub
      page_count = $pages.Count
      pages      = $pages
    }) | Out-Null
  }

  return @($result)
}

function Get-OrphanPages {
  param(
    $PagePaths
  )

  $normalized = @(Convert-ToStringArray -InputObject $PagePaths)
  $orphans = New-Object System.Collections.Generic.List[string]

  foreach ($path in $normalized) {
    $route = Convert-PagePathToRoute -Path $path
    $depth = Get-RouteDepth -Route $route
    $lower = $path.ToLowerInvariant()

    $isRootIndex = ($route -eq '/')
    $isHubIndex = $false
    if ($lower.StartsWith('src/hubs/') -and ($lower.EndsWith('/index.md') -or $lower.EndsWith('/index.njk') -or $lower.EndsWith('/index.html'))) {
      $isHubIndex = $true
    }

    if (-not $isRootIndex -and -not $isHubIndex -and $depth -ge 2) {
      $orphans.Add([string]$path) | Out-Null
    }
  }

  return @($orphans | Sort-Object -Unique | ForEach-Object { [string]$_ })
}

function Get-StructureScore {
  param(
    [Parameter(Mandatory=$true)]$MinimalAudit,
    [Parameter(Mandatory=$true)]$PagePaths,
    [Parameter(Mandatory=$true)]$HubMap,
    [Parameter(Mandatory=$true)]$OrphanPages,
    [Parameter(Mandatory=$true)]$EmptyDirectories
  )

  $score = 100

  if (-not $MinimalAudit.has_src) { $score -= 40 }
  if (-not $MinimalAudit.has_hubs) { $score -= 10 }
  if (-not $MinimalAudit.has_index_md -and -not $MinimalAudit.has_index_njk) { $score -= 25 }

  $pageCount = @($PagePaths).Count
  $hubCount = @($HubMap).Count
  $orphanCount = @($OrphanPages).Count
  $emptyDirCount = @($EmptyDirectories).Count

  if ($pageCount -gt 0) {
    $orphanPenalty = [Math]::Min(25, [int][Math]::Ceiling(($orphanCount * 100.0 / $pageCount) / 5))
    $score -= $orphanPenalty
  }

  if ($hubCount -eq 0 -and $pageCount -ge 20) {
    $score -= 10
  }

  $score -= [Math]::Min(10, $emptyDirCount)

  if ($score -lt 0) { $score = 0 }
  if ($score -gt 100) { $score = 100 }

  return $score
}

function Get-AuditV2 {
  param(
    $Repo,
    $TreeItems
  )

  $repoText = [string]$Repo
  $items = @(Normalize-TreeItems -TreeItems $TreeItems)
  $paths = @($items | ForEach-Object { [string]$_.path })
  $blobPaths = @($items | Where-Object { $_.type -eq 'blob' } | ForEach-Object { [string]$_.path })

  $hasSrc = @($paths | Where-Object { $_ -eq 'src' -or $_.StartsWith('src/') }).Count -gt 0
  $hasHubs = @($paths | Where-Object { $_ -eq 'src/hubs' -or $_.StartsWith('src/hubs/') }).Count -gt 0
  $hasIndexMd = @($blobPaths | Where-Object { $_ -eq 'src/index.md' }).Count -gt 0
  $hasIndexNjk = @($blobPaths | Where-Object { $_ -eq 'src/index.njk' }).Count -gt 0

  $pagePaths = @(Get-PagePaths -TreeItems $items)
  $hubMap = @(Get-HubMap -PagePaths $pagePaths)
  $orphanPages = @(Get-OrphanPages -PagePaths $pagePaths)
  $emptyDirs = @(Get-EmptyDirectories -TreeItems $items)

  $routeDepthMap = New-Object System.Collections.Generic.List[object]
  $maxDepth = 0
  foreach ($page in $pagePaths) {
    $route = Convert-PagePathToRoute -Path ([string]$page)
    $depth = Get-RouteDepth -Route $route
    if ($depth -gt $maxDepth) { $maxDepth = $depth }

    $routeDepthMap.Add([pscustomobject]@{
      path  = [string]$page
      route = [string]$route
      depth = [int]$depth
    }) | Out-Null
  }

  $warnings = New-Object System.Collections.Generic.List[string]
  $issues = New-Object System.Collections.Generic.List[string]

  if (-not $hasSrc) {
    $issues.Add('MISSING_PATH: src/') | Out-Null
  }
  if (-not $hasHubs) {
    $warnings.Add('MISSING_PATH: src/hubs/') | Out-Null
  }
  if (-not $hasIndexMd -and -not $hasIndexNjk) {
    $issues.Add('MISSING_ENTRY: src/index.md or src/index.njk') | Out-Null
  }
  if (@($orphanPages).Count -gt 0) {
    $warnings.Add("ORPHAN_PAGES: $(@($orphanPages).Count)") | Out-Null
  }
  if (@($emptyDirs).Count -gt 0) {
    $warnings.Add("EMPTY_DIRS: $(@($emptyDirs).Count)") | Out-Null
  }

  $minimalAudit = [pscustomobject]@{
    repo                = $repoText
    has_src             = $hasSrc
    has_hubs            = $hasHubs
    has_index_md        = $hasIndexMd
    has_index_njk       = $hasIndexNjk
    page_count          = @($pagePaths).Count
    hub_page_count      = @($pagePaths | Where-Object { $_.StartsWith('src/hubs/') }).Count
    warnings            = @($warnings)
    pass_minimal_audit  = ($hasSrc -and ($hasIndexMd -or $hasIndexNjk))
  }

  $structureScore = Get-StructureScore `
    -MinimalAudit $minimalAudit `
    -PagePaths @($pagePaths) `
    -HubMap @($hubMap) `
    -OrphanPages @($orphanPages) `
    -EmptyDirectories @($emptyDirs)

  return [pscustomobject]@{
    audit_version        = 'v2'
    repo                 = $repoText
    has_src              = $hasSrc
    has_hubs             = $hasHubs
    has_index_md         = $hasIndexMd
    has_index_njk        = $hasIndexNjk
    page_count           = @($pagePaths).Count
    hub_page_count       = @($pagePaths | Where-Object { $_.StartsWith('src/hubs/') }).Count
    hubs_total           = @($hubMap).Count
    hub_map              = @($hubMap)
    orphan_pages_count   = @($orphanPages).Count
    orphan_pages         = @($orphanPages)
    empty_dirs_count     = @($emptyDirs).Count
    empty_dirs           = @($emptyDirs)
    max_route_depth      = $maxDepth
    route_depth_map      = @($routeDepthMap)
    structure_score      = $structureScore
    issues               = @($issues)
    warnings             = @($warnings)
    pass_minimal_audit   = [bool]$minimalAudit.pass_minimal_audit
  }
}

function Invoke-SiteAuditor {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$ReportsDir,
    [Parameter(Mandatory=$true)][string[]]$RepoList,
    [Parameter(Mandatory=$false)][string]$Token
  )

  $ErrorActionPreference = 'Stop'

  if (Test-Path $ReportsDir) {
    Remove-Item $ReportsDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null

  $tokenPresent = -not [string]::IsNullOrWhiteSpace($Token)
  $patPreflight = [ordered]@{
    timestamp      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    token_present  = $tokenPresent
    token_length   = if ($tokenPresent) { $Token.Length } else { 0 }
  }
  Save-JsonFile -Path (Join-Path $ReportsDir 'pat-preflight.json') -Object $patPreflight

  $userResult = Invoke-GitHubApi -Method 'GET' -Url 'https://api.github.com/user' -Token $Token
  Write-StepTrace -Path (Join-Path $ReportsDir '00_user.json') -Repo '__identity__' -StepName 'user' -Result $userResult

  $summary = New-Object System.Collections.Generic.List[object]
  $auditResults = New-Object System.Collections.Generic.List[object]

  $repoItems = @(Convert-ToStringArray -InputObject $RepoList)

  foreach ($repo in $repoItems) {
    $repoSlug = $repo.Replace('/','__')

    $repoMetaUrl = "https://api.github.com/repos/$repo"
    $repoMeta = Invoke-GitHubApi -Method 'GET' -Url $repoMetaUrl -Token $Token
    Write-StepTrace `
      -Path (Join-Path $ReportsDir "$repoSlug`__01_repo_meta.json") `
      -Repo $repo `
      -StepName 'repo_meta' `
      -Result $repoMeta

    $defaultBranch = $null
    $repoPrivate = $null
    $repoId = $null

    if ($repoMeta.ok -and $repoMeta.body_json) {
      try { $defaultBranch = [string]$repoMeta.body_json.default_branch } catch {}
      try { $repoPrivate = [bool]$repoMeta.body_json.private } catch {}
      try { $repoId = [string]$repoMeta.body_json.id } catch {}
    }

    $branchResult = $null
    $commitSha = $null
    $treeSha = $null

    if (-not [string]::IsNullOrWhiteSpace($defaultBranch)) {
      $branchUrl = "https://api.github.com/repos/$repo/branches/$defaultBranch"
      $branchResult = Invoke-GitHubApi -Method 'GET' -Url $branchUrl -Token $Token
      Write-StepTrace `
        -Path (Join-Path $ReportsDir "$repoSlug`__02_branch.json") `
        -Repo $repo `
        -StepName 'branch' `
        -Result $branchResult `
        -Extra @{ default_branch = $defaultBranch }

      if ($branchResult.ok -and $branchResult.body_json) {
        try { $commitSha = [string]$branchResult.body_json.commit.sha } catch {}
        try { $treeSha   = [string]$branchResult.body_json.commit.commit.tree.sha } catch {}
      }
    }
    else {
      Save-JsonFile -Path (Join-Path $ReportsDir "$repoSlug`__02_branch.json") -Object ([ordered]@{
        timestamp      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        repo           = $repo
        step_name      = 'branch'
        skipped        = $true
        reason         = 'default_branch_missing'
        default_branch = $defaultBranch
      })
    }

    $treeResult = $null
    $treeItems = @()
    $inventoryCount = 0
    $stats = $null
    $auditV2 = $null

    if (-not [string]::IsNullOrWhiteSpace($treeSha)) {
      $treeUrl = "https://api.github.com/repos/$repo/git/trees/${treeSha}?recursive=1"
      $treeResult = Invoke-GitHubApi -Method 'GET' -Url $treeUrl -Token $Token
      Write-StepTrace `
        -Path (Join-Path $ReportsDir "$repoSlug`__03_tree.json") `
        -Repo $repo `
        -StepName 'tree' `
        -Result $treeResult `
        -Extra @{ default_branch = $defaultBranch; commit_sha = $commitSha; tree_sha = $treeSha }

      if ($treeResult.ok -and $treeResult.body_json) {
        try {
          $treeItems = @($treeResult.body_json.tree)
        }
        catch {
          $treeItems = @()
        }

        $stats = Get-RepoInventoryStats -TreeItems $treeItems
        $inventoryCount = $stats.inventory_count
        $auditV2 = Get-AuditV2 -Repo $repo -TreeItems $treeItems
      }
    }
    else {
      Save-JsonFile -Path (Join-Path $ReportsDir "$repoSlug`__03_tree.json") -Object ([ordered]@{
        timestamp      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        repo           = $repo
        step_name      = 'tree'
        skipped        = $true
        reason         = 'tree_sha_missing'
        default_branch = $defaultBranch
        commit_sha     = $commitSha
        tree_sha       = $treeSha
      })
    }

    $zipHeadResult = $null
    if (-not [string]::IsNullOrWhiteSpace($defaultBranch)) {
      $zipUrl = "https://api.github.com/repos/$repo/zipball/$defaultBranch"
      $zipHeadResult = Invoke-GitHubApi -Method 'HEAD' -Url $zipUrl -Token $Token -RawText
      Write-StepTrace `
        -Path (Join-Path $ReportsDir "$repoSlug`__04_zipball_head.json") `
        -Repo $repo `
        -StepName 'zipball_head' `
        -Result $zipHeadResult `
        -Extra @{ default_branch = $defaultBranch }
    }
    else {
      Save-JsonFile -Path (Join-Path $ReportsDir "$repoSlug`__04_zipball_head.json") -Object ([ordered]@{
        timestamp      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        repo           = $repo
        step_name      = 'zipball_head'
        skipped        = $true
        reason         = 'default_branch_missing'
        default_branch = $defaultBranch
      })
    }

    if ($null -eq $stats) {
      $stats = [pscustomobject]@{
        inventory_count = 0
        md_files        = 0
        html_files      = 0
        njk_files       = 0
        js_files        = 0
        css_files       = 0
        json_files      = 0
        image_files     = 0
        src_files       = 0
        hub_files       = 0
        root_files      = 0
      }
    }

    if ($null -eq $auditV2) {
      $auditV2 = [pscustomobject]@{
        audit_version       = 'v2'
        repo                = $repo
        has_src             = $false
        has_hubs            = $false
        has_index_md        = $false
        has_index_njk       = $false
        page_count          = 0
        hub_page_count      = 0
        hubs_total          = 0
        hub_map             = @()
        orphan_pages_count  = 0
        orphan_pages        = @()
        empty_dirs_count    = 0
        empty_dirs          = @()
        max_route_depth     = 0
        route_depth_map     = @()
        structure_score     = 0
        issues              = @('AUDIT_V2_SKIPPED')
        warnings            = @()
        pass_minimal_audit  = $false
      }
    }

    $auditResult = [ordered]@{
      repo                = $repo
      audit_version       = 'v2'
      default_branch      = $defaultBranch
      commit_sha          = $commitSha
      tree_sha            = $treeSha
      inventory           = $stats
      audit_v2            = $auditV2
      pass_fetch          = [bool](($repoMeta.ok) -and ($treeResult) -and ($treeResult.ok) -and ($inventoryCount -gt 0))
      pass_minimal_audit  = [bool]$auditV2.pass_minimal_audit
    }

    Save-JsonFile -Path (Join-Path $ReportsDir "$repoSlug`__audit_result.json") -Object $auditResult
    $auditResults.Add([pscustomobject]$auditResult) | Out-Null

    $repoSummary = [ordered]@{
      repo                 = $repo
      audit_version        = 'v2'
      repo_meta_ok         = [bool]($repoMeta.ok)
      repo_meta_status     = $repoMeta.status_code
      default_branch       = $defaultBranch
      branch_ok            = if ($branchResult) { [bool]($branchResult.ok) } else { $false }
      branch_status        = if ($branchResult) { $branchResult.status_code } else { $null }
      commit_sha           = $commitSha
      tree_sha             = $treeSha
      tree_ok              = if ($treeResult) { [bool]($treeResult.ok) } else { $false }
      tree_status          = if ($treeResult) { $treeResult.status_code } else { $null }
      inventory_count      = $inventoryCount
      md_files             = $stats.md_files
      html_files           = $stats.html_files
      njk_files            = $stats.njk_files
      hub_files            = $stats.hub_files
      has_src              = $auditV2.has_src
      has_hubs             = $auditV2.has_hubs
      has_index_md         = $auditV2.has_index_md
      has_index_njk        = $auditV2.has_index_njk
      hubs_total           = $auditV2.hubs_total
      orphan_pages_count   = $auditV2.orphan_pages_count
      empty_dirs_count     = $auditV2.empty_dirs_count
      max_route_depth      = $auditV2.max_route_depth
      structure_score      = $auditV2.structure_score
      minimal_audit_ok     = [bool]$auditV2.pass_minimal_audit
      zipball_head_ok      = if ($zipHeadResult) { [bool]($zipHeadResult.ok) } else { $false }
      zipball_head_status  = if ($zipHeadResult) { $zipHeadResult.status_code } else { $null }
      private              = $repoPrivate
      repo_id              = $repoId
      pass_fetch           = [bool](($repoMeta.ok) -and ($treeResult) -and ($treeResult.ok) -and ($inventoryCount -gt 0))
    }

    $summary.Add([pscustomobject]$repoSummary) | Out-Null
  }

  Save-JsonFile -Path (Join-Path $ReportsDir 'pipeline-summary.json') -Object $summary
  Save-JsonFile -Path (Join-Path $ReportsDir 'audit_result.json') -Object $auditResults

  $reposPassFetch = @($summary | Where-Object { $_.pass_fetch }).Count
  $reposPassMinimal = @($summary | Where-Object { $_.minimal_audit_ok }).Count

  $reportLines = New-Object System.Collections.Generic.List[string]
  $reportLines.Add('SITE_AUDITOR REPORT v2') | Out-Null
  $reportLines.Add('') | Out-Null
  $reportLines.Add("Repos total: $($summary.Count)") | Out-Null
  $reportLines.Add("Repos pass fetch: $reposPassFetch") | Out-Null
  $reportLines.Add("Repos pass minimal audit: $reposPassMinimal") | Out-Null
  $reportLines.Add('') | Out-Null

  foreach ($item in $summary) {
    $reportLines.Add("Repo: $($item.repo)") | Out-Null
    $reportLines.Add("  repo_meta_status: $($item.repo_meta_status)") | Out-Null
    $reportLines.Add("  branch_status: $($item.branch_status)") | Out-Null
    $reportLines.Add("  tree_status: $($item.tree_status)") | Out-Null
    $reportLines.Add("  inventory_count: $($item.inventory_count)") | Out-Null
    $reportLines.Add("  md_files: $($item.md_files)") | Out-Null
    $reportLines.Add("  html_files: $($item.html_files)") | Out-Null
    $reportLines.Add("  njk_files: $($item.njk_files)") | Out-Null
    $reportLines.Add("  hub_files: $($item.hub_files)") | Out-Null
    $reportLines.Add("  hubs_total: $($item.hubs_total)") | Out-Null
    $reportLines.Add("  orphan_pages_count: $($item.orphan_pages_count)") | Out-Null
    $reportLines.Add("  empty_dirs_count: $($item.empty_dirs_count)") | Out-Null
    $reportLines.Add("  max_route_depth: $($item.max_route_depth)") | Out-Null
    $reportLines.Add("  structure_score: $($item.structure_score)") | Out-Null
    $reportLines.Add("  has_src: $($item.has_src)") | Out-Null
    $reportLines.Add("  has_hubs: $($item.has_hubs)") | Out-Null
    $reportLines.Add("  has_index_md: $($item.has_index_md)") | Out-Null
    $reportLines.Add("  has_index_njk: $($item.has_index_njk)") | Out-Null
    $reportLines.Add("  pass_fetch: $($item.pass_fetch)") | Out-Null
    $reportLines.Add("  minimal_audit_ok: $($item.minimal_audit_ok)") | Out-Null
    $reportLines.Add('') | Out-Null
  }

  Save-TextFile -Path (Join-Path $ReportsDir 'REPORT.txt') -Text ($reportLines -join [Environment]::NewLine)

  $overallStatus = if ($reposPassMinimal -gt 0) {
    'PASS_AUDIT_V2'
  }
  elseif ($reposPassFetch -gt 0) {
    'PASS_FETCH_ONLY'
  }
  else {
    'FAIL_FETCH'
  }

  $final = [ordered]@{
    timestamp              = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    agent_name             = 'SITE_AUDITOR_AGENT'
    mode                   = 'FIXED_LIST_AUDIT_V2'
    audit_version          = 'v2'
    token_present          = $tokenPresent
    user_ok                = [bool]$userResult.ok
    user_status            = $userResult.status_code
    repos_total            = $summary.Count
    repos_pass_fetch       = $reposPassFetch
    repos_pass_minimal     = $reposPassMinimal
    overall_status         = $overallStatus
  }

  Save-JsonFile -Path (Join-Path $ReportsDir 'final-status.json') -Object $final

  Write-Host "=== FINAL STATUS ==="
  $final | ConvertTo-Json -Depth 20

  if ($reposPassFetch -le 0) {
    throw "FAIL_FETCH: no repo reached inventory_count > 0"
  }
}
