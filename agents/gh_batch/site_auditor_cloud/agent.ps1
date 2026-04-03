
$ErrorActionPreference = "Stop"

<#
GOAL
- Judge site as product without over-reporting false P0.

INPUTS
- reports/visual_manifest.json from capture.mjs
- optional env TARGET_REPO_PATH / GITHUB_WORKSPACE

OUTPUTS
- route_inventory.json
- visual_findings.json
- route_scores.json
- page_type_audit.json
- repo_audit.json
- decision_summary.json
- REPORT.txt

PASS
- Writes all report files based on available evidence.

FAIL
- Missing visual_manifest.json or unreadable json.
#>

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Normalize {
    param($x)
    if ($null -eq $x) { return @() }
    return @($x)
}

function Get-Int {
    param($v)
    try { return [int]$v } catch { return 0 }
}

function Join-ListText {
    param($items)
    $arr = @()
    foreach ($i in (Normalize $items)) {
        $s = [string]$i
        if (-not [string]::IsNullOrWhiteSpace($s)) { $arr += $s }
    }
    return ($arr | Select-Object -Unique) -join ", "
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

function Get-TextFromItem {
    param($i)

    $parts = @()
    foreach ($name in @('visibleText','bodyText','text','body_text','innerText','pageText')) {
        $v = $i.PSObject.Properties[$name]
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v.Value)) {
            $parts += [string]$v.Value
        }
    }
    return ($parts -join " `n")
}

function Test-RepoCandidate {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'src'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'package.json'))) { return $false }
    return $true
}

function Get-RepoCandidateScore {
    param([string]$Path, [string]$ScriptRoot)

    if (-not (Test-RepoCandidate $Path)) { return -1 }

    $score = 0
    $full = [System.IO.Path]::GetFullPath($Path)
    $scriptFull = [System.IO.Path]::GetFullPath($ScriptRoot)

    if ($full -ne $scriptFull) { $score += 5 }
    if ($full -notmatch 'site_auditor_cloud|agents[\\/]gh_batch|e-factory-agent') { $score += 10 }
    if (Test-Path -LiteralPath (Join-Path $Path '00__AI__CONTROL_LOOP.md')) { $score += 20 }
    if (Test-Path -LiteralPath (Join-Path $Path 'STRATEGY_BOARD.md')) { $score += 20 }
    if (Test-Path -LiteralPath (Join-Path $Path 'src/_data')) { $score += 10 }
    if ($full -match 'automation-kb|target_repo') { $score += 15 }

    return $score
}

function Get-RepoRoot {
    param([string]$StartPath)

    $candidates = New-Object System.Collections.ArrayList
    $scriptRoot = Get-ScriptRoot

    foreach ($p in @(
        $env:TARGET_REPO_PATH,
        (Join-Path $env:GITHUB_WORKSPACE 'target_repo'),
        $env:GITHUB_WORKSPACE,
        $StartPath,
        (Split-Path -Parent $StartPath),
        (Split-Path -Parent (Split-Path -Parent $StartPath)),
        (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $StartPath)))
    )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) {
            [void]$candidates.Add($p)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -and (Test-Path -LiteralPath $env:GITHUB_WORKSPACE)) {
        try {
            foreach ($child in (Get-ChildItem -LiteralPath $env:GITHUB_WORKSPACE -Directory -ErrorAction SilentlyContinue)) {
                [void]$candidates.Add($child.FullName)
            }
        }
        catch {}
    }

    $best = $null
    $bestScore = -1
    $seen = @{}

    foreach ($cand in $candidates) {
        if ([string]::IsNullOrWhiteSpace($cand)) { continue }
        try { $full = [System.IO.Path]::GetFullPath($cand) } catch { $full = $cand }
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        $score = Get-RepoCandidateScore -Path $full -ScriptRoot $scriptRoot
        if ($score -gt $bestScore) {
            $best = $full
            $bestScore = $score
        }
    }

    if ($null -ne $best) { return $best }
    return $StartPath
}

function Get-Weight {
    param([string]$Path)
    if ($Path -eq '/' -or $Path -eq '/hubs/' -or $Path -eq '/search/') { return 'critical' }
    if ($Path -eq '/tools/' -or $Path -eq '/start-here/') { return 'high' }
    return 'normal'
}

function Get-PageType {
    param([string]$Path, [int]$Len, [int]$Links)

    if ($Path -eq '/') { return 'ENTRY' }
    if ($Path -eq '/hubs/') { return 'ROUTER' }
    if ($Path -eq '/search/') { return 'FLOW' }
    if ($Path -eq '/tools/') { return 'TOOL' }
    if ($Path -eq '/start-here/') { return 'ENTRY_GUIDE' }
    if ($Len -lt 120 -and $Links -lt 2) { return 'EMPTY' }
    if ($Len -lt 260 -and $Links -lt 4) { return 'SCAFFOLD' }
    return 'ARTICLE'
}

function Get-RouteBand {
    param([string]$Path, [int]$Len, [int]$Links)

    switch ($Path) {
        '/' {
            if ($Len -lt 140 -and $Links -lt 2) { return 'bad' }
            if ($Len -lt 240 -or $Links -lt 3) { return 'thin' }
            return 'ok'
        }
        '/search/' {
            if ($Len -lt 100 -and $Links -lt 3) { return 'bad' }
            if ($Len -lt 180 -or $Links -lt 5) { return 'thin' }
            return 'ok'
        }
        '/hubs/' {
            if ($Len -lt 180 -and $Links -lt 4) { return 'bad' }
            if ($Len -lt 420 -or $Links -lt 8) { return 'thin' }
            return 'ok'
        }
        default {
            if ($Len -lt 180 -and $Links -lt 3) { return 'bad' }
            if ($Len -lt 360 -or $Links -lt 4) { return 'thin' }
            return 'ok'
        }
    }
}

function Get-VisualState {
    param([string]$Path, [int]$Len, [int]$Images, [int]$Links)

    if ($Len -lt 110 -and $Links -lt 2 -and $Images -eq 0) { return 'empty' }
    if ($Len -lt 220 -and $Links -lt 3 -and $Images -eq 0) { return 'thin' }
    if ($Images -eq 0) { return 'weak' }
    return 'ok'
}

function Test-UiContamination {
    param([string]$Title, [string]$Path, [string]$VisibleText)

    $markers = @(
        'Built with',
        'Edit on GitHub',
        'BATCH-',
        'PATCH_',
        'PATCH NOTES',
        'CONTROL LOOP',
        'README APPLY',
        'debug',
        'internal use only'
    )

    $haystack = @()
    if (-not [string]::IsNullOrWhiteSpace($Title)) { $haystack += $Title }
    if (-not [string]::IsNullOrWhiteSpace($Path)) { $haystack += $Path }
    if (-not [string]::IsNullOrWhiteSpace($VisibleText)) { $haystack += $VisibleText }
    $joined = ($haystack -join "`n")

    $hits = @()
    foreach ($m in $markers) {
        if ($joined -like "*$m*") { $hits += $m }
    }

    return @($hits | Select-Object -Unique)
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
            screenshot_count = Get-Int $i.screenshotCount
        }
    }
    return @($out)
}

function Find-SuspiciousTopLevelItems {
    param([string]$RepoRoot)

    $hits = @()
    $topItems = Get-ChildItem -LiteralPath $RepoRoot -Force -ErrorAction SilentlyContinue
    $allow = @('README.md','package.json','package-lock.json','.gitignore','.github','src','assets','scripts','nav.js','index.11ty.js','CONTRIBUTING.md')

    $namePatterns = @(
        '^BATCH_',
        '^DELETE_LIST',
        '^PATCH_NOTES',
        '^README_APPLY',
        '^SHA256SUMS',
        '^00__ALL_MEMORY',
        '\.patch$',
        '^tmp',
        '^draft'
    )

    foreach ($item in $topItems) {
        $name = [string]$item.Name
        if ($allow -contains $name) { continue }
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
    $dirs = @('.state', 'done', 'failed', 'good', 'inbox', 'log', 'logs', 'deliver')
    foreach ($d in $dirs) {
        $path = Join-Path $RepoRoot $d
        if (Test-Path -LiteralPath $path) { $hits += $d }
    }
    return @($hits | Select-Object -Unique)
}

function Analyze-RepoHygiene {
    param([string]$RepoRoot)

    $topSuspicious = Find-SuspiciousTopLevelItems -RepoRoot $RepoRoot
    $mixedDirs = Find-MixedLayerDirectories -RepoRoot $RepoRoot

    return [pscustomobject]@{
        repo_root = $RepoRoot
        suspicious_top_level_items = @($topSuspicious)
        mixed_layer_directories = @($mixedDirs)
        repo_clean = ($topSuspicious.Count -eq 0)
        architecture_clean = ($mixedDirs.Count -eq 0)
    }
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
        $pageType = Get-PageType -Path $path -Len $len -Links $links
        $band = Get-RouteBand -Path $path -Len $len -Links $links
        $visual = Get-VisualState -Path $path -Len $len -Images $img -Links $links
        $visibleText = Get-TextFromItem $i
        $uiHits = Test-UiContamination -Title $title -Path $path -VisibleText $visibleText

        $hasProblemFrame = $false
        $hasSolutionDepth = $false
        $hasNextStep = $false
        $hasValueStatement = $false
        $hasCTA = $false
        $thinUtility = $false

        switch ($path) {
            '/' {
                $hasProblemFrame = ($len -ge 180)
                $hasValueStatement = ($len -ge 180)
                $hasNextStep = ($links -ge 3)
                $hasCTA = ($links -ge 3)
                $hasSolutionDepth = ($len -ge 420)
            }
            '/hubs/' {
                $hasProblemFrame = ($len -ge 260)
                $hasValueStatement = ($len -ge 260)
                $hasNextStep = ($links -ge 8)
                $hasCTA = ($links -ge 6)
                $hasSolutionDepth = ($len -ge 700)
            }
            '/search/' {
                $hasProblemFrame = ($len -ge 140)
                $hasValueStatement = ($len -ge 140)
                $hasNextStep = ($links -ge 5)
                $hasCTA = ($links -ge 3)
                $hasSolutionDepth = ($len -ge 320)
                $thinUtility = ($len -lt 260 -or $links -lt 6)
            }
            default {
                $hasProblemFrame = ($len -ge 260)
                $hasValueStatement = ($len -ge 260)
                $hasNextStep = ($links -ge 4)
                $hasCTA = ($links -ge 4)
                $hasSolutionDepth = ($len -ge 700)
            }
        }

        $fakePage = $false
        if ($band -eq 'ok' -and $len -ge 500 -and (-not $hasProblemFrame -or -not $hasNextStep)) {
            $fakePage = $true
        }

        $fakeShell = $false
        if (($pageType -eq 'SCAFFOLD' -or $pageType -eq 'EMPTY') -and $links -gt 0 -and $len -lt 260) {
            $fakeShell = $true
        }

        $deadEnd = $false
        if (-not $hasNextStep -and $links -lt 3) { $deadEnd = $true }

        $out += [pscustomobject]@{
            path = $path
            title = $title
            len = $len
            img = $img
            links = $links
            visual = $visual
            band = $band
            page_type = $pageType
            ui_contamination = ($uiHits.Count -gt 0)
            ui_contamination_hits = @($uiHits)
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

        $out += [pscustomobject]@{
            path = $p
            weight = Get-Weight $p
            band = Get-RouteBand -Path $p -Len $len -Links $links
            len = $len
            images = Get-Int $i.images
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
        if ($s.path -eq '/hubs/' -and $s.band -ne 'bad' -and $s.links -ge 8) { $router = $true }
        if ($s.path -eq '/search/' -and $s.band -ne 'bad' -and $s.links -ge 5) { $flow = $true }
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

        if (-not $f.has_problem_frame -and $f.band -eq 'bad') {
            $intentFailRoutes += $f.path
        }

        if ($f.fake_page) { $fakePageRoutes += $f.path }
        if ($f.fake_shell) { $fakeShellRoutes += $f.path }
        if ($f.dead_end) { $deadEndRoutes += $f.path }
        if ($f.ui_contamination) { $uiContaminationRoutes += $f.path }
        if (-not $f.has_cta -and $f.links -lt 3) { $ctaMissingRoutes += $f.path }
        if ($f.band -eq 'thin' -and -not $f.fake_page -and -not $f.fake_shell) { $thinButValidRoutes += $f.path }
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
        if ($s.weight -eq 'critical' -and $s.band -eq 'bad') { $criticalBad += $s.path }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.visual -eq 'empty') { $visualEmpty += $f.path }
    }

    $failedGates = @()
    if (-not $repoAudit.repo_clean) { $failedGates += 'REPO_CLEANLINESS' }
    if (-not $repoAudit.architecture_clean) { $failedGates += 'ARCHITECTURE' }
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
    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $core = 'Repo is not a clean product boundary and mixes product with internal/dev artifacts.'
    }
    elseif ($ux.ui_contamination_routes.Count -gt 0) {
        $core = 'Public pages contain development or internal UI contamination.'
    }
    elseif ($ux.homepage_fail) {
        $core = 'Homepage exists but is too weak as the main entry point.'
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
    if (-not $repoAudit.repo_clean) {
        $p0 += 'Repo cleanliness failed: internal or build artifacts are present in the product repo.'
    }
    if (-not $repoAudit.architecture_clean) {
        $p0 += 'Architecture boundary failed: product content is mixed with scripts/tools/runtime layers.'
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $p0 += 'UI contamination detected on public pages (' + (Join-ListText $ux.ui_contamination_routes) + ').'
    }
    if ($ux.homepage_fail) {
        $p0 += 'Homepage is too weak as a usable entry point.'
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
        $p0 += 'Fake pages detected: pages look present but do not function as real product pages (' + (Join-ListText $ux.fake_page_routes) + ').'
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
        $p0 += 'Some routes appear truly empty (' + (Join-ListText $visualEmpty) + ').'
    }
    $p0 = @($p0 | Select-Object -Unique | Select-Object -First 12)

    $p1 = @()
    if ($ux.intent_fail_routes.Count -gt 0) {
        $p1 += 'Some pages do not clearly frame the user problem or use-case (' + (Join-ListText $ux.intent_fail_routes) + ').'
    }
    if ($ux.thin_but_valid_routes.Count -gt 0) {
        $p1 += 'Some routes are valid but too thin for product use (' + (Join-ListText $ux.thin_but_valid_routes) + ').'
    }
    if ($criticalBad -contains '/hubs/') {
        $p1 += 'Hubs behave like a thin page, not a real router.'
    }
    if ($criticalBad -contains '/search/') {
        $p1 += 'Search behaves like a thin utility page, not a discovery system.'
    }
    if (-not $sys.conversion_exists) {
        $p1 += 'No dedicated monetization or conversion route detected in the current structure.'
    }
    $p1 = @($p1 | Select-Object -Unique | Select-Object -First 6)

    $do = @()
    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $do += 'Separate product files from internal, batch, test, and governance artifacts in the repo.'
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $do += 'Remove development and internal UI contamination from public pages.'
    }
    if ($ux.homepage_fail) {
        $do += 'Strengthen homepage as entry point with value statement, route options, and a clearer primary CTA.'
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
        $do += 'Replace fake pages and empty shells with real problem → solution → next-step structure.'
    }
    $do = @($do | Select-Object -Unique | Select-Object -First 5)

    $readiness = [pscustomobject]@{
        indexing = 'NO'
        traffic = 'NO'
        monetization = 'NO'
    }

    if ($sys.system_exists -and $sys.entry_exists -and $sys.router_exists -and $sys.flow_exists -and $repoAudit.repo_clean -and $repoAudit.architecture_clean -and $ux.ui_contamination_routes.Count -eq 0) {
        $readiness.indexing = 'PARTIAL'
        $readiness.traffic = 'PARTIAL'
    }
    if ($sys.conversion_exists) { $readiness.monetization = 'PARTIAL' }

    $missing = @()
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

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep = Join-Path $root 'reports'
    if (-not (Test-Path -LiteralPath $rep)) {
        New-Item -ItemType Directory -Path $rep | Out-Null
    }

    $repoRoot = Get-RepoRoot -StartPath $root
    $repoAudit = Analyze-RepoHygiene -RepoRoot $repoRoot

    $manifestPath = Join-Path $rep 'visual_manifest.json'
    $manifest = Read-JsonFile -Path $manifestPath

    $items = Normalize $manifest
    $inventory = Build-RouteInventory -items $items
    $find = Get-Findings -items $items
    $scores = Get-Scores -items $items
    $pageTypeAudit = Build-PageTypeAudit -findings $find
    $dec = Decide -scores $scores -findings $find -repoAudit $repoAudit

    $inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $rep 'route_inventory.json') -Encoding UTF8
    $find | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'visual_findings.json') -Encoding UTF8
    $scores | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $rep 'route_scores.json') -Encoding UTF8
    $pageTypeAudit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rep 'page_type_audit.json') -Encoding UTF8
    $repoAudit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $rep 'repo_audit.json') -Encoding UTF8
    $dec | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $rep 'decision_summary.json') -Encoding UTF8
    Write-DecisionText -Path (Join-Path $rep 'REPORT.txt') -dec $dec

    Write-Host ('REPORT repo_root=' + $repoRoot)
    Write-Host ('REPORT system_verdict=' + $dec.system_verdict)
}
