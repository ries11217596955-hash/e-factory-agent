$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Normalize {
    param($x)
    return @($x)
}

function Normalize-PathText {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $Path
    }
}

function Test-IsSameOrChildPath {
    param(
        [string]$ParentPath,
        [string]$ChildPath
    )

    $parent = Normalize-PathText $ParentPath
    $child = Normalize-PathText $ChildPath
    if ([string]::IsNullOrWhiteSpace($parent) -or [string]::IsNullOrWhiteSpace($child)) { return $false }

    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    if ($child.Equals($parent, $cmp)) { return $true }

    $trimmed = $parent.TrimEnd([char]'/', [char]'\')
    return $child.StartsWith($trimmed + [System.IO.Path]::DirectorySeparatorChar, $cmp) -or
           $child.StartsWith($trimmed + [char]'/', $cmp) -or
           $child.StartsWith($trimmed + [char]'\', $cmp)
}

function Get-Int {
    param($v)
    try { return [int]$v } catch { return 0 }
}

function Join-ListText {
    param($items)
    $arr = @()
    foreach ($i in (Normalize $items)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$i)) {
            $arr += [string]$i
        }
    }
    return ($arr -join ", ")
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object,
        [int]$Depth = 12
    )
    $json = $Object | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-PathFromItem {
    param($i)

    if ($null -ne $i.route_path -and -not [string]::IsNullOrWhiteSpace([string]$i.route_path)) {
        return [string]$i.route_path
    }

    if ($null -ne $i.url -and -not [string]::IsNullOrWhiteSpace([string]$i.url)) {
        try {
            $u = [uri]([string]$i.url)
            if ([string]::IsNullOrWhiteSpace($u.AbsolutePath)) { return "/" }
            return [string]$u.AbsolutePath
        }
        catch {
            return [string]$i.url
        }
    }

    return ""
}

function Get-BodyTextFromItem {
    param($i)

    $parts = @()
    foreach ($prop in @('visibleText', 'bodyText', 'text', 'contentText', 'pageText')) {
        if ($null -ne $i.$prop -and -not [string]::IsNullOrWhiteSpace([string]$i.$prop)) {
            $parts += [string]$i.$prop
        }
    }

    return (($parts -join " `n").Trim())
}

function Test-IsLikelyProductRepo {
    param(
        [string]$Path,
        [string]$AgentRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (Test-IsSameOrChildPath -ParentPath $AgentRoot -ChildPath $Path) { return $false }

    $src = Join-Path $Path 'src'
    $pkg = Join-Path $Path 'package.json'
    $eleventy = Join-Path $Path '.eleventy.js'

    if (-not (Test-Path -LiteralPath $src -PathType Container)) { return $false }
    if ((Test-Path -LiteralPath $pkg -PathType Leaf) -or (Test-Path -LiteralPath $eleventy -PathType Leaf)) {
        return $true
    }

    return $false
}

function Get-RepoMeta {
    param(
        [string]$Slug,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Slug)) { return $null }
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'SITE_AUDITOR_AGENT'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers['Authorization'] = "Bearer $Token"
    }

    $url = "https://api.github.com/repos/$Slug"
    try {
        return Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Expand-SingleRootArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestPath
    )

    if (Test-Path -LiteralPath $DestPath) {
        Remove-Item -LiteralPath $DestPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestPath | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestPath -Force

    $entries = @(Get-ChildItem -LiteralPath $DestPath -Force)
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
        return $entries[0].FullName
    }

    return $DestPath
}

function Get-DefaultRepoSlug {
    param([string]$AgentRoot)

    foreach ($envName in @('TARGET_REPO_SLUG', 'SITE_REPO_SLUG', 'SITE_REPO', 'EXPECTED_REPO')) {
        $value = [string](Get-Item -Path ("Env:" + $envName) -ErrorAction SilentlyContinue).Value
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }

    $reposFile = Join-Path $AgentRoot 'repos.fixed.json'
    if (Test-Path -LiteralPath $reposFile -PathType Leaf) {
        try {
            $repos = Read-JsonFile -Path $reposFile
            foreach ($repo in (Normalize $repos)) {
                $slug = [string]$repo
                if ([string]::IsNullOrWhiteSpace($slug)) { continue }
                if ($slug -match '/automation-kb$') { return $slug }
            }
            foreach ($repo in (Normalize $repos)) {
                $slug = [string]$repo
                if ([string]::IsNullOrWhiteSpace($slug)) { continue }
                if ($slug -notmatch '/e-factory-agent$' -and $slug -notmatch '/e-factory-memory$') {
                    return $slug
                }
            }
        }
        catch {}
    }

    return ''
}

function Get-BoundRepoRoot {
    param([string]$AgentRoot)

    $result = [ordered]@{
        ok = $false
        repo_root = ''
        repo_source = ''
        repo_slug = ''
        binding_error = ''
    }

    foreach ($envName in @('TARGET_REPO_PATH', 'SITE_REPO_PATH')) {
        $candidate = [string](Get-Item -Path ("Env:" + $envName) -ErrorAction SilentlyContinue).Value
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = Normalize-PathText $candidate
            if (Test-IsLikelyProductRepo -Path $candidate -AgentRoot $AgentRoot) {
                $result.ok = $true
                $result.repo_root = $candidate
                $result.repo_source = $envName
                return [pscustomobject]$result
            }
        }
    }

    $workspace = [string](Get-Item -Path 'Env:GITHUB_WORKSPACE' -ErrorAction SilentlyContinue).Value
    if (-not [string]::IsNullOrWhiteSpace($workspace)) {
        $workspace = Normalize-PathText $workspace
        $candidates = @(
            (Join-Path $workspace 'target_repo'),
            (Join-Path $workspace 'automation-kb'),
            (Join-Path $workspace 'automation-kb-main'),
            (Join-Path (Split-Path -Parent $workspace) 'automation-kb'),
            (Join-Path (Split-Path -Parent $workspace) 'automation-kb-main')
        )

        foreach ($candidate in $candidates) {
            if (Test-IsLikelyProductRepo -Path $candidate -AgentRoot $AgentRoot) {
                $result.ok = $true
                $result.repo_root = (Normalize-PathText $candidate)
                $result.repo_source = 'workspace_candidate'
                return [pscustomobject]$result
            }
        }

        try {
            $dirs = Get-ChildItem -LiteralPath $workspace -Directory -Force
            foreach ($dir in $dirs) {
                if (Test-IsLikelyProductRepo -Path $dir.FullName -AgentRoot $AgentRoot) {
                    $result.ok = $true
                    $result.repo_root = (Normalize-PathText $dir.FullName)
                    $result.repo_source = 'workspace_scan'
                    return [pscustomobject]$result
                }
            }
        }
        catch {}
    }

    $slug = Get-DefaultRepoSlug -AgentRoot $AgentRoot
    $result.repo_slug = $slug
    $token = [string](Get-Item -Path 'Env:GH_PAT' -ErrorAction SilentlyContinue).Value

    if (-not [string]::IsNullOrWhiteSpace($slug) -and -not [string]::IsNullOrWhiteSpace($token)) {
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("site-auditor-target-" + [guid]::NewGuid().ToString('N'))
        $zipPath = Join-Path $tmpRoot 'repo.zip'
        $extractDir = Join-Path $tmpRoot 'repo'
        New-Item -ItemType Directory -Path $tmpRoot | Out-Null

        $headers = @{
            'Accept' = 'application/vnd.github+json'
            'User-Agent' = 'SITE_AUDITOR_AGENT'
            'X-GitHub-Api-Version' = '2022-11-28'
            'Authorization' = "Bearer $token"
        }

        try {
            $meta = Get-RepoMeta -Slug $slug -Token $token
            if ($null -eq $meta) {
                throw "REPO_META_UNAVAILABLE: $slug"
            }

            $zipUrl = [string]$meta.zipball_url
            if ([string]::IsNullOrWhiteSpace($zipUrl)) {
                throw "ZIPBALL_URL_MISSING: $slug"
            }

            Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zipPath -ErrorAction Stop | Out-Null
            $repoPath = Expand-SingleRootArchive -ZipPath $zipPath -DestPath $extractDir

            if (-not (Test-IsLikelyProductRepo -Path $repoPath -AgentRoot $AgentRoot)) {
                throw "FETCHED_REPO_NOT_PRODUCT_ROOT: $repoPath"
            }

            $result.ok = $true
            $result.repo_root = (Normalize-PathText $repoPath)
            $result.repo_source = 'github_zipball'
            $result.repo_slug = $slug
            return [pscustomobject]$result
        }
        catch {
            $result.binding_error = [string]$_.Exception.Message
            return [pscustomobject]$result
        }
    }

    if ([string]::IsNullOrWhiteSpace($slug)) {
        $result.binding_error = 'TARGET_REPO_NOT_RESOLVED'
    }
    elseif ([string]::IsNullOrWhiteSpace($token)) {
        $result.binding_error = 'GH_PAT_MISSING_FOR_REPO_FETCH'
    }
    else {
        $result.binding_error = 'TARGET_REPO_BINDING_FAILED'
    }

    return [pscustomobject]$result
}

function Get-Weight {
    param([string]$p)

    if ($p -eq '/' -or $p -eq '/hubs/' -or $p -eq '/search/') { return 'critical' }
    if ($p -eq '/tools/' -or $p -eq '/start-here/') { return 'high' }
    return 'normal'
}

function Build-RouteInventory {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $out += [pscustomobject]@{
            path = Get-PathFromItem $i
            length = Get-Int $i.bodyTextLength
            images = Get-Int $i.images
            links = Get-Int $i.links
            title = [string]$i.title
        }
    }
    return @($out)
}

function Find-SuspiciousTopLevelItems {
    param([string]$RepoRoot)

    $hits = @()
    $topItems = Get-ChildItem -LiteralPath $RepoRoot -Force

    $namePatterns = @(
        '^BATCH_',
        '^DELETE_LIST',
        '^PATCH_NOTES',
        '^README_APPLY',
        '^SHA256SUMS',
        '\.patch$',
        '^tmp',
        '^draft',
        '^spec$'
    )

    foreach ($item in $topItems) {
        $name = [string]$item.Name
        foreach ($pattern in $namePatterns) {
            if ($name -match $pattern) {
                $hits += $name
                break
            }
        }
    }

    return @($hits | Select-Object -Unique)
}

function Find-MixedLayerDirectories {
    param([string]$RepoRoot)

    $hits = @()
    $dirs = @('scripts', 'tools', 'test', '.state', 'done', 'failed', 'good', 'inbox', 'log', 'logs')
    foreach ($d in $dirs) {
        $path = Join-Path $RepoRoot $d
        if (Test-Path -LiteralPath $path) {
            $hits += $d
        }
    }

    return @($hits | Select-Object -Unique)
}

function Analyze-RepoHygiene {
    param(
        [string]$AgentRoot,
        $RepoBinding
    )

    if ($null -eq $RepoBinding -or -not $RepoBinding.ok) {
        return [pscustomobject]@{
            repo_root = if ($null -ne $RepoBinding) { $RepoBinding.repo_root } else { '' }
            repo_source = if ($null -ne $RepoBinding) { $RepoBinding.repo_source } else { '' }
            repo_slug = if ($null -ne $RepoBinding) { $RepoBinding.repo_slug } else { '' }
            target_repo_bound = $false
            binding_error = if ($null -ne $RepoBinding) { $RepoBinding.binding_error } else { 'TARGET_REPO_BINDING_FAILED' }
            suspicious_top_level_items = @()
            mixed_layer_directories = @()
            repo_clean = $false
            architecture_clean = $false
        }
    }

    $repoRoot = [string]$RepoBinding.repo_root
    if (-not (Test-IsLikelyProductRepo -Path $repoRoot -AgentRoot $AgentRoot)) {
        return [pscustomobject]@{
            repo_root = $repoRoot
            repo_source = [string]$RepoBinding.repo_source
            repo_slug = [string]$RepoBinding.repo_slug
            target_repo_bound = $false
            binding_error = 'BOUND_PATH_IS_NOT_PRODUCT_REPO'
            suspicious_top_level_items = @()
            mixed_layer_directories = @()
            repo_clean = $false
            architecture_clean = $false
        }
    }

    $topSuspicious = Find-SuspiciousTopLevelItems -RepoRoot $repoRoot
    $mixedDirs = Find-MixedLayerDirectories -RepoRoot $repoRoot

    return [pscustomobject]@{
        repo_root = $repoRoot
        repo_source = [string]$RepoBinding.repo_source
        repo_slug = [string]$RepoBinding.repo_slug
        target_repo_bound = $true
        binding_error = ''
        suspicious_top_level_items = @($topSuspicious)
        mixed_layer_directories = @($mixedDirs)
        repo_clean = ($topSuspicious.Count -eq 0)
        architecture_clean = ($mixedDirs.Count -eq 0)
    }
}

function Get-PageType {
    param(
        [string]$Path,
        [int]$Len,
        [int]$Links
    )

    if ($Path -eq '/') { return 'ENTRY' }
    if ($Path -eq '/hubs/') { return 'ROUTER' }
    if ($Path -eq '/search/') { return 'FLOW' }
    if ($Path -eq '/tools/') { return 'TOOL' }
    if ($Path -eq '/start-here/') { return 'ENTRY_GUIDE' }
    if ($Len -lt 80 -and $Links -lt 2) { return 'EMPTY' }
    if ($Len -lt 180 -and $Links -lt 4) { return 'SCAFFOLD' }
    return 'ARTICLE'
}

function Get-Band {
    param(
        [string]$Path,
        [int]$Len,
        [int]$Links,
        [int]$Images
    )

    if ($Path -eq '/') {
        if ($Len -lt 120 -and $Links -lt 3) { return 'bad' }
        if ($Len -lt 220 -and $Links -lt 4) { return 'thin' }
        if ($Links -ge 4) { return 'ok' }
        return 'thin'
    }

    if ($Path -eq '/search/') {
        if ($Len -lt 90 -and $Links -lt 4) { return 'bad' }
        if ($Links -ge 6) { return 'ok' }
        if ($Len -ge 140) { return 'thin' }
        return 'bad'
    }

    if ($Len -lt 150 -and $Links -lt 3) { return 'bad' }
    if ($Len -lt 350 -and $Links -lt 6 -and $Images -eq 0) { return 'thin' }
    return 'ok'
}

function Get-VisualBand {
    param(
        [string]$Path,
        [int]$Len,
        [int]$Images,
        [int]$Links
    )

    if ($Images -gt 0) { return 'ok' }
    if ($Path -eq '/' -and $Links -ge 4) { return 'weak' }
    if ($Path -eq '/search/' -and ($Len -ge 120 -or $Links -ge 6)) { return 'weak' }
    if ($Len -lt 120 -and $Links -lt 3) { return 'empty' }
    return 'weak'
}

function Test-UiContamination {
    param(
        [string]$Title,
        [string]$Path,
        [string]$BodyText
    )

    $markers = @(
        'Built with',
        'Edit on GitHub',
        'BATCH-',
        'PATCH_',
        'PATCH NOTES',
        'CONTROL LOOP',
        'README APPLY',
        'debug',
        'internal'
    )

    $hits = @()
    $sources = @($Title, $Path, $BodyText)

    foreach ($m in $markers) {
        foreach ($source in $sources) {
            if ([string]::IsNullOrWhiteSpace($source)) { continue }
            if ($source -like "*$m*") {
                $hits += $m
                break
            }
        }
    }

    return @($hits | Select-Object -Unique)
}

function Get-Findings {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $len = Get-Int $i.bodyTextLength
        $img = Get-Int $i.images
        $links = Get-Int $i.links
        $path = Get-PathFromItem $i
        $title = [string]$i.title
        $bodyText = Get-BodyTextFromItem $i

        $band = Get-Band -Path $path -Len $len -Links $links -Images $img
        $visual = Get-VisualBand -Path $path -Len $len -Images $img -Links $links
        $pageType = Get-PageType -Path $path -Len $len -Links $links
        $uiContaminationHits = Test-UiContamination -Title $title -Path $path -BodyText $bodyText
        $uiContamination = ($uiContaminationHits.Count -gt 0)

        $hasProblemFrame = $false
        $hasSolutionDepth = $false
        $hasNextStep = $false
        $hasValueStatement = $false
        $hasCTA = $false

        if ($len -ge 180) { $hasProblemFrame = $true }
        if ($len -ge 900 -or ($len -ge 500 -and $links -ge 10)) { $hasSolutionDepth = $true }
        if ($links -ge 4 -or $path -eq '/start-here/' -or $path -eq '/search/' -or $path -eq '/hubs/') { $hasNextStep = $true }

        if ($path -eq '/') {
            if ($len -ge 180 -and $links -ge 4) { $hasValueStatement = $true }
        }
        else {
            if ($len -ge 180) { $hasValueStatement = $true }
        }

        if ($links -ge 4 -or $path -match '/start-here/|/pricing/|/contact/|/demo/|/consult|/signup|/subscribe|/tools/|/hubs/|/search/') {
            $hasCTA = $true
        }

        $fakePage = $false
        if ($len -ge 350 -and (-not $hasProblemFrame -or -not $hasNextStep)) {
            $fakePage = $true
        }

        $fakeShell = $false
        if (($pageType -eq 'SCAFFOLD' -or $pageType -eq 'EMPTY') -and $links -gt 0 -and $len -lt 180) {
            $fakeShell = $true
        }

        $deadEnd = $false
        if (-not $hasNextStep -and $links -lt 2) {
            $deadEnd = $true
        }

        $thinUtility = $false
        if ($path -eq '/search/' -and $band -ne 'bad' -and $len -lt 260 -and $links -ge 6) {
            $thinUtility = $true
        }

        $out += [pscustomobject]@{
            path = $path
            title = $title
            len = $len
            img = $img
            links = $links
            visual = $visual
            band = $band
            page_type = $pageType
            ui_contamination = $uiContamination
            ui_contamination_hits = @($uiContaminationHits)
            has_problem_frame = $hasProblemFrame
            has_solution_depth = $hasSolutionDepth
            has_next_step = $hasNextStep
            has_value_statement = $hasValueStatement
            has_cta = $hasCTA
            fake_page = $fakePage
            fake_shell = $fakeShell
            dead_end = $deadEnd
            thin_utility = $thinUtility
        }
    }

    return @($out)
}

function Get-Scores {
    param($items)

    $out = @()
    foreach ($i in (Normalize $items)) {
        $p = Get-PathFromItem $i
        $len = Get-Int $i.bodyTextLength
        $links = Get-Int $i.links
        $images = Get-Int $i.images
        $band = Get-Band -Path $p -Len $len -Links $links -Images $images

        $out += [pscustomobject]@{
            path = $p
            weight = Get-Weight $p
            band = $band
            len = $len
            images = $images
            links = $links
        }
    }

    return @($out)
}

function Analyze-System {
    param($scores, $findings)

    $router = $false
    $flow = $false
    $nextStep = $false
    $conversion = $false
    $entry = $false
    $visualTrust = $false

    foreach ($s in (Normalize $scores)) {
        if ($s.path -eq '/hubs/' -and $s.band -eq 'ok') { $router = $true }
        if ($s.path -eq '/search/' -and ($s.band -eq 'ok' -or $s.band -eq 'thin')) { $flow = $true }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.path -eq '/' -and $f.has_value_statement -and $f.has_next_step) { $entry = $true }
        if ($f.has_next_step) { $nextStep = $true }
        if ($f.img -gt 0) { $visualTrust = $true }
        if ($f.has_cta) { $conversion = $true }
    }

    return [pscustomobject]@{
        system_exists = ($router -and $flow -and $nextStep)
        entry_exists = $entry
        router_exists = $router
        flow_exists = $flow
        next_step_exists = $nextStep
        conversion_exists = $conversion
        visual_trust_exists = $visualTrust
    }
}

function Analyze-UserReality {
    param($findings)

    $homepageFail = $false
    $intentFailRoutes = @()
    $fakePageRoutes = @()
    $fakeShellRoutes = @()
    $deadEndRoutes = @()
    $uiContaminationRoutes = @()
    $entryClarityRoutes = @()
    $ctaMissingRoutes = @()
    $thinButValidRoutes = @()

    foreach ($f in (Normalize $findings)) {
        if ($f.path -eq '/') {
            if (-not $f.has_value_statement -or -not $f.has_next_step) {
                $homepageFail = $true
                $entryClarityRoutes += $f.path
            }
        }

        if ($f.band -eq 'bad' -and (-not $f.has_problem_frame -or -not $f.has_solution_depth)) {
            $intentFailRoutes += $f.path
        }

        if ($f.fake_page) {
            $fakePageRoutes += $f.path
        }

        if ($f.fake_shell) {
            $fakeShellRoutes += $f.path
        }

        if ($f.dead_end) {
            $deadEndRoutes += $f.path
        }

        if ($f.ui_contamination) {
            $uiContaminationRoutes += $f.path
        }

        if (-not $f.has_cta -and $f.band -eq 'bad') {
            $ctaMissingRoutes += $f.path
        }

        if ($f.band -eq 'thin' -and -not $f.fake_shell -and -not $f.dead_end) {
            $thinButValidRoutes += $f.path
        }
    }

    return [pscustomobject]@{
        homepage_fail = $homepageFail
        intent_fail_routes = @($intentFailRoutes | Select-Object -Unique)
        fake_page_routes = @($fakePageRoutes | Select-Object -Unique)
        fake_shell_routes = @($fakeShellRoutes | Select-Object -Unique)
        dead_end_routes = @($deadEndRoutes | Select-Object -Unique)
        ui_contamination_routes = @($uiContaminationRoutes | Select-Object -Unique)
        entry_clarity_routes = @($entryClarityRoutes | Select-Object -Unique)
        cta_missing_routes = @($ctaMissingRoutes | Select-Object -Unique)
        thin_but_valid_routes = @($thinButValidRoutes | Select-Object -Unique)
    }
}

function Build-PageTypeAudit {
    param($findings)

    $out = @()
    foreach ($f in (Normalize $findings)) {
        $out += [pscustomobject]@{
            path = $f.path
            page_type = $f.page_type
            band = $f.band
            visual = $f.visual
            fake_shell = $f.fake_shell
            fake_page = $f.fake_page
            dead_end = $f.dead_end
            ui_contamination = $f.ui_contamination
            has_cta = $f.has_cta
            has_value_statement = $f.has_value_statement
            has_problem_frame = $f.has_problem_frame
            has_solution_depth = $f.has_solution_depth
            has_next_step = $f.has_next_step
            thin_utility = $f.thin_utility
        }
    }
    return @($out)
}

function Decide {
    param($scores, $findings, $repoAudit)

    $sys = Analyze-System -scores $scores -findings $findings
    $ux = Analyze-UserReality -findings $findings

    $criticalBad = @()
    $visualEmpty = @()

    foreach ($s in (Normalize $scores)) {
        if ($s.weight -eq 'critical' -and $s.band -eq 'bad') {
            $criticalBad += $s.path
        }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.visual -eq 'empty') {
            $visualEmpty += $f.path
        }
    }

    $failedGates = @()

    if (-not $repoAudit.target_repo_bound) { $failedGates += 'REPO_BINDING' }
    if ($repoAudit.target_repo_bound -and -not $repoAudit.repo_clean) { $failedGates += 'REPO_CLEANLINESS' }
    if ($repoAudit.target_repo_bound -and -not $repoAudit.architecture_clean) { $failedGates += 'ARCHITECTURE' }
    if (-not $sys.system_exists) { $failedGates += 'SYSTEM' }
    if (-not $sys.entry_exists) { $failedGates += 'ENTRY' }
    if (-not $sys.router_exists) { $failedGates += 'ROUTER' }
    if (-not $sys.flow_exists) { $failedGates += 'FLOW' }
    if (-not $sys.conversion_exists) { $failedGates += 'CONVERSION' }
    if (-not $sys.visual_trust_exists) { $failedGates += 'VISUAL' }
    if ($ux.homepage_fail) { $failedGates += 'ENTRY_QUALITY' }
    if ($ux.intent_fail_routes.Count -gt 0) { $failedGates += 'INTENT' }
    if ($ux.fake_page_routes.Count -gt 0) { $failedGates += 'FAKE_PAGE' }
    if ($ux.fake_shell_routes.Count -gt 0) { $failedGates += 'FAKE_SHELL' }
    if ($ux.dead_end_routes.Count -gt 0) { $failedGates += 'FLOW_DEAD_END' }
    if ($ux.ui_contamination_routes.Count -gt 0) { $failedGates += 'UI_CONTAMINATION' }
    if ($ux.cta_missing_routes.Count -gt 0) { $failedGates += 'CTA_MISSING' }

    $core = 'Site does not function as a decision system.'

    if (-not $repoAudit.target_repo_bound) {
        $core = 'Repo audit is invalid because the target site repo is not bound.'
    }
    elseif (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $core = 'Repo is not a clean product boundary and mixes product with internal/dev artifacts.'
    }
    elseif ($ux.ui_contamination_routes.Count -gt 0) {
        $core = 'Public pages contain development or internal UI contamination.'
    }
    elseif ($ux.homepage_fail) {
        $core = 'Homepage does not function as a usable entry point.'
    }
    elseif ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) {
        $core = 'Some pages create an illusion of content but do not function as real product pages.'
    }
    elseif (-not $sys.system_exists) {
        $core = 'Site does not function as a decision system.'
    }
    elseif ($criticalBad.Count -gt 0) {
        $core = 'Critical routes lack sufficient depth and break navigation flow.'
    }

    $p0 = @()
    if (-not $repoAudit.target_repo_bound) {
        $p0 += 'Repo binding failed: repo audit is not looking at the target site repo.'
        if (-not [string]::IsNullOrWhiteSpace([string]$repoAudit.binding_error)) {
            $p0 += ('Repo binding error: ' + [string]$repoAudit.binding_error)
        }
    }
    if ($repoAudit.target_repo_bound -and -not $repoAudit.repo_clean) {
        $p0 += 'Repo cleanliness failed: internal or build artifacts are present in the product repo.'
    }
    if ($repoAudit.target_repo_bound -and -not $repoAudit.architecture_clean) {
        $p0 += 'Architecture boundary failed: product content is mixed with scripts/tools/test layers.'
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $p0 += 'UI contamination detected on public pages (' + (Join-ListText $ux.ui_contamination_routes) + ').'
    }
    if ($ux.homepage_fail) {
        $p0 += 'Homepage does not function as a usable entry point.'
    }
    if (-not $sys.router_exists) {
        $p0 += 'Router layer is missing or ineffective.'
    }
    if (-not $sys.flow_exists) {
        $p0 += 'Discovery flow is missing or ineffective.'
    }
    if (-not $sys.conversion_exists) {
        $p0 += 'Conversion layer is missing.'
    }
    if (-not $sys.visual_trust_exists) {
        $p0 += 'Visual trust layer is missing on key pages.'
    }
    if ($ux.fake_shell_routes.Count -gt 0) {
        $p0 += 'Empty shell or scaffold pages detected (' + (Join-ListText $ux.fake_shell_routes) + ').'
    }
    if ($ux.fake_page_routes.Count -gt 0) {
        $p0 += 'Fake pages detected: pages look present but do not frame a problem or next step (' + (Join-ListText $ux.fake_page_routes) + ').'
    }
    if ($ux.dead_end_routes.Count -gt 0) {
        $p0 += 'User flow breaks on dead-end pages (' + (Join-ListText $ux.dead_end_routes) + ').'
    }
    if ($ux.cta_missing_routes.Count -gt 0) {
        $p0 += 'No clear CTA or next action detected on some weak routes (' + (Join-ListText $ux.cta_missing_routes) + ').'
    }
    if ($criticalBad.Count -gt 0) {
        $p0 += 'Critical routes lack depth (' + (Join-ListText $criticalBad) + ').'
    }
    if ($visualEmpty.Count -gt 0) {
        $p0 += 'Some key routes appear empty (' + (Join-ListText $visualEmpty) + ').'
    }
    $p0 = @($p0 | Select-Object -Unique | Select-Object -First 12)

    $p1 = @()
    if ($ux.intent_fail_routes.Count -gt 0) {
        $p1 += 'Some pages do not clearly frame the user problem or use-case (' + (Join-ListText $ux.intent_fail_routes) + ').'
    }
    if ($criticalBad -contains '/hubs/') {
        $p1 += 'Hubs behave like a thin page, not a real router.'
    }
    if ($criticalBad -contains '/search/' -or $ux.thin_but_valid_routes -contains '/search/') {
        $p1 += 'Search behaves like a thin utility page, not a full discovery system.'
    }
    if (-not $sys.conversion_exists) {
        $p1 += 'No dedicated monetization or conversion route detected in the current structure.'
    }
    $p1 = @($p1 | Select-Object -Unique | Select-Object -First 6)

    $do = @()
    if (-not $repoAudit.target_repo_bound) {
        $do += 'Bind the target site repo explicitly before repo audit, or fetch it through GitHub API with GH_PAT.'
    }
    if ($repoAudit.target_repo_bound -and (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean)) {
        $do += 'Separate product files from internal, batch, test, and governance artifacts in the repo.'
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $do += 'Remove development and internal UI contamination from public pages.'
    }
    if ($ux.homepage_fail) {
        $do += 'Rebuild homepage as entry point with value statement, route options, and CTA.'
    }
    if (-not $sys.router_exists -or ($criticalBad -contains '/hubs/')) {
        $do += 'Rebuild /hubs/ as an intent-based router, not a flat list.'
    }
    if (-not $sys.flow_exists -or ($criticalBad -contains '/search/')) {
        $do += 'Rebuild /search/ as a discovery flow with guidance and entry points.'
    }
    if (-not $sys.conversion_exists) {
        $do += 'Add a visible conversion layer on key pages.'
    }
    if (-not $sys.visual_trust_exists) {
        $do += 'Add visual trust blocks, previews, or screenshots on key pages.'
    }
    if ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) {
        $do += 'Replace fake pages and empty shells with real problem to solution to next-step structure.'
    }
    $do = @($do | Select-Object -Unique | Select-Object -First 5)

    $readiness = [pscustomobject]@{
        indexing = 'NO'
        traffic = 'NO'
        monetization = 'NO'
    }

    if ($repoAudit.target_repo_bound -and $sys.system_exists -and $sys.entry_exists -and $sys.router_exists -and $sys.flow_exists -and $repoAudit.repo_clean -and $repoAudit.architecture_clean -and $ux.ui_contamination_routes.Count -eq 0) {
        $readiness.indexing = 'PARTIAL'
        $readiness.traffic = 'PARTIAL'
    }

    if ($sys.conversion_exists) {
        $readiness.monetization = 'PARTIAL'
    }

    $missing = @()
    if (-not $repoAudit.target_repo_bound) { $missing += 'valid_repo_binding' }
    if (-not $sys.router_exists) { $missing += 'router_layer' }
    if (-not $sys.flow_exists) { $missing += 'discovery_flow' }
    if (-not $sys.conversion_exists) { $missing += 'conversion_layer' }
    if (-not $sys.visual_trust_exists) { $missing += 'visual_trust_layer' }
    if (-not $sys.entry_exists) { $missing += 'entry_structure' }
    if ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) { $missing += 'real_problem_solution_pages' }
    if ($ux.ui_contamination_routes.Count -gt 0) { $missing += 'clean_public_ui' }
    if ($ux.cta_missing_routes.Count -gt 0) { $missing += 'clear_cta_layer' }
    $missing = @($missing | Select-Object -Unique)

    return [pscustomobject]@{
        system_verdict = 'FAIL'
        failed_gates = @($failedGates | Select-Object -Unique)
        core = $core
        p0 = @($p0)
        p1 = @($p1)
        do = @($do)
        readiness = $readiness
        missing_components = @($missing)
        repo_audit = $repoAudit
        system_status = $sys
        user_reality = $ux
    }
}

function Write-DecisionText {
    param([string]$Path, $dec)

    $lines = @()
    $lines += 'SYSTEM VERDICT'
    $lines += $dec.system_verdict
    $lines += ''
    $lines += 'FAILED GATES'
    foreach ($x in (Normalize $dec.failed_gates)) { $lines += '- ' + $x }
    $lines += ''
    $lines += 'CORE'
    $lines += $dec.core
    $lines += ''
    $lines += 'P0'
    foreach ($x in (Normalize $dec.p0)) { $lines += '- ' + $x }
    $lines += ''
    $lines += 'P1'
    foreach ($x in (Normalize $dec.p1)) { $lines += '- ' + $x }
    $lines += ''
    $lines += 'DO NEXT'
    $i = 1
    foreach ($x in (Normalize $dec.do)) {
        $lines += ('{0}. {1}' -f $i, $x)
        $i++
    }
    $lines += ''
    $lines += 'READINESS'
    $lines += ('indexing: ' + $dec.readiness.indexing)
    $lines += ('traffic: ' + $dec.readiness.traffic)
    $lines += ('monetization: ' + $dec.readiness.monetization)
    $lines += ''
    $lines += 'MISSING COMPONENTS'
    foreach ($x in (Normalize $dec.missing_components)) { $lines += '- ' + $x }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep = Join-Path $root 'reports'
    if (-not (Test-Path -LiteralPath $rep)) {
        New-Item -ItemType Directory -Path $rep | Out-Null
    }

    $repoBinding = Get-BoundRepoRoot -AgentRoot $root
    $repoAudit = Analyze-RepoHygiene -AgentRoot $root -RepoBinding $repoBinding

    $manifestPath = Join-Path $rep 'visual_manifest.json'
    $manifest = Read-JsonFile -Path $manifestPath

    $items = Normalize $manifest
    $inventory = Build-RouteInventory -items $items
    $find = Get-Findings -items $items
    $scores = Get-Scores -items $items
    $pageTypeAudit = Build-PageTypeAudit -findings $find
    $dec = Decide -scores $scores -findings $find -repoAudit $repoAudit

    Write-JsonFile -Path (Join-Path $rep 'route_inventory.json') -Object $inventory -Depth 6
    Write-JsonFile -Path (Join-Path $rep 'visual_findings.json') -Object $find -Depth 8
    Write-JsonFile -Path (Join-Path $rep 'route_scores.json') -Object $scores -Depth 6
    Write-JsonFile -Path (Join-Path $rep 'page_type_audit.json') -Object $pageTypeAudit -Depth 8
    Write-JsonFile -Path (Join-Path $rep 'repo_audit.json') -Object $repoAudit -Depth 8
    Write-JsonFile -Path (Join-Path $rep 'decision_summary.json') -Object $dec -Depth 10
    Write-DecisionText -Path (Join-Path $rep 'REPORT.txt') -dec $dec

    Write-Host 'DONE'
}
