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

  $json = $Object | ConvertTo-Json -Depth 50
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
    [Parameter(Mandatory=$true)][array]$TreeItems
  )

  $blobItems = @($TreeItems | Where-Object { $_.type -eq 'blob' })

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

function Get-MinimalAudit {
  param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][array]$TreeItems
  )

  $paths = @($TreeItems | ForEach-Object { [string]$_.path })
  $blobPaths = @($TreeItems | Where-Object { $_.type -eq 'blob' } | ForEach-Object { [string]$_.path })

  $hasSrc = @($paths | Where-Object { $_ -eq 'src' -or $_.StartsWith('src/') }).Count -gt 0
  $hasHubs = @($paths | Where-Object { $_ -eq 'src/hubs' -or $_.StartsWith('src/hubs/') }).Count -gt 0
  $hasIndexMd = @($blobPaths | Where-Object { $_ -eq 'src/index.md' }).Count -gt 0
  $hasIndexNjk = @($blobPaths | Where-Object { $_ -eq 'src/index.njk' }).Count -gt 0

  $contentPages = @(
    $blobPaths | Where-Object {
      $_.StartsWith('src/') -and (
        $_.ToLowerInvariant().EndsWith('.md') -or
        $_.ToLowerInvariant().EndsWith('.njk') -or
        $_.ToLowerInvariant().EndsWith('.html')
      )
    }
  )

  $hubPages = @(
    $blobPaths | Where-Object {
      $_.StartsWith('src/hubs/') -and (
        $_.ToLowerInvariant().EndsWith('.md') -or
        $_.ToLowerInvariant().EndsWith('.njk') -or
        $_.ToLowerInvariant().EndsWith('.html')
      )
    }
  )

  $warnings = New-Object System.Collections.Generic.List[string]
  if (-not $hasSrc)      { $warnings.Add('MISSING_PATH: src/') | Out-Null }
  if (-not $hasHubs)     { $warnings.Add('MISSING_PATH: src/hubs/') | Out-Null }
  if (-not $hasIndexMd -and -not $hasIndexNjk) { $warnings.Add('MISSING_ENTRY: src/index.md or src/index.njk') | Out-Null }

  $passMinimal = $hasSrc -and ($hasIndexMd -or $hasIndexNjk)

  return [pscustomobject]@{
    repo                = $Repo
    has_src             = $hasSrc
    has_hubs            = $hasHubs
    has_index_md        = $hasIndexMd
    has_index_njk       = $hasIndexNjk
    page_count          = $contentPages.Count
    hub_page_count      = $hubPages.Count
    warnings            = @($warnings)
    pass_minimal_audit  = $passMinimal
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

  foreach ($repo in $RepoList) {
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
    $minimalAudit = $null

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
        $minimalAudit = Get-MinimalAudit -Repo $repo -TreeItems $treeItems
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

    if ($null -eq $minimalAudit) {
      $minimalAudit = [pscustomobject]@{
        repo               = $repo
        has_src            = $false
        has_hubs           = $false
        has_index_md       = $false
        has_index_njk      = $false
        page_count         = 0
        hub_page_count     = 0
        warnings           = @('MINIMAL_AUDIT_SKIPPED')
        pass_minimal_audit = $false
      }
    }

    $auditResult = [ordered]@{
      repo                = $repo
      default_branch      = $defaultBranch
      commit_sha          = $commitSha
      tree_sha            = $treeSha
      inventory           = $stats
      minimal_audit       = $minimalAudit
      pass_fetch          = [bool](($repoMeta.ok) -and ($treeResult) -and ($treeResult.ok) -and ($inventoryCount -gt 0))
      pass_minimal_audit  = [bool]$minimalAudit.pass_minimal_audit
    }

    Save-JsonFile -Path (Join-Path $ReportsDir "$repoSlug`__audit_result.json") -Object $auditResult
    $auditResults.Add([pscustomobject]$auditResult) | Out-Null

    $repoSummary = [ordered]@{
      repo                 = $repo
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
      has_src              = $minimalAudit.has_src
      has_hubs             = $minimalAudit.has_hubs
      has_index_md         = $minimalAudit.has_index_md
      has_index_njk        = $minimalAudit.has_index_njk
      minimal_audit_ok     = [bool]$minimalAudit.pass_minimal_audit
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
  $reportLines.Add('SITE_AUDITOR REPORT') | Out-Null
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
    'PASS_MINIMAL_AUDIT'
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
    mode                   = 'FIXED_LIST_MINIMAL_AUDIT'
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
