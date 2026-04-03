$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Get-RepoRoot {
    param([string]$StartPath)

    $current = $StartPath
    for ($i = 0; $i -lt 6; $i++) {
        if (-not $current) { break }

        $gitDir = Join-Path $current ".git"
        $pkg = Join-Path $current "package.json"
        $src = Join-Path $current "src"

        if ((Test-Path $gitDir) -or (Test-Path $pkg) -or (Test-Path $src)) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return $StartPath
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Normalize {
    param($x)
    return @($x)
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
        } catch {
            return [string]$i.url
        }
    }

    return ""
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

function Get-Weight {
    param([string]$p)

    if ($p -eq "/" -or $p -eq "/hubs/" -or $p -eq "/search/") { return "critical" }
    if ($p -eq "/tools/" -or $p -eq "/start-here/") { return "high" }
    return "normal"
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
    $topItems = Get-ChildItem -Path $RepoRoot -Force

    $namePatterns = @(
        '^BATCH_',
        '^DELETE_LIST',
        '^PATCH_NOTES',
        '^README_APPLY',
        '^SHA256SUMS',
        '^CONTROL_LOOP',
        '^STRATEGY_BOARD',
        '^00__AI__',
        '^00__ALL_MEMORY',
        '\.patch$',
        '^test-',
        '^tmp',
        '^draft',
        '^spec'
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
    $dirs = @("scripts", "tools", "test", "docs", ".state", "done", "failed", "good", "inbox", "log", "logs")
    foreach ($d in $dirs) {
        $path = Join-Path $RepoRoot $d
        if (Test-Path $path) {
            $hits += $d
        }
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

function Get-PageType {
    param(
        [string]$Path,
        [int]$Len,
        [int]$Links
    )

    if ($Path -eq "/") { return "ENTRY" }
    if ($Path -eq "/hubs/") { return "ROUTER" }
    if ($Path -eq "/search/") { return "FLOW" }
    if ($Path -eq "/tools/") { return "TOOL" }
    if ($Path -eq "/start-here/") { return "ENTRY_GUIDE" }
    if ($Len -lt 120 -and $Links -lt 3) { return "EMPTY" }
    if ($Len -lt 350 -and $Links -lt 6) { return "SCAFFOLD" }
    return "ARTICLE"
}

function Test-UiContamination {
    param(
        [string]$Title,
        [string]$Path
    )

    $markers = @(
        'Built with',
        'Edit on GitHub',
        'BATCH-',
        'PATCH_',
        'PATCH NOTES',
        'CONTROL LOOP',
        'README APPLY'
    )

    $hits = @()
    foreach ($m in $markers) {
        if (-not [string]::IsNullOrWhiteSpace($Title) -and $Title -like "*$m*") {
            $hits += $m
        }
        if (-not [string]::IsNullOrWhiteSpace($Path) -and $Path -like "*$m*") {
            $hits += $m
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

        $visual = "ok"
        if ($img -eq 0 -and $len -lt 350) {
            $visual = "empty"
        }
        elseif ($img -eq 0) {
            $visual = "weak"
        }

        $pageType = Get-PageType -Path $path -Len $len -Links $links
        $uiContaminationHits = Test-UiContamination -Title $title -Path $path
        $uiContamination = ($uiContaminationHits.Count -gt 0)

        $hasProblemFrame = $false
        $hasSolutionDepth = $false
        $hasNextStep = $false
        $hasValueStatement = $false
        $hasCTA = $false

        if ($len -ge 450) { $hasProblemFrame = $true }
        if ($len -ge 700) { $hasSolutionDepth = $true }
        if ($links -ge 8) { $hasNextStep = $true }

        if ($path -eq "/") {
            if ($len -ge 700 -and $links -ge 10) { $hasValueStatement = $true }
        }
        else {
            if ($len -ge 500) { $hasValueStatement = $true }
        }

        if ($links -ge 12 -or $path -match '/start-here/|/pricing/|/contact/|/demo/|/consult|/signup|/subscribe') {
            $hasCTA = $true
        }

        $fakePage = $false
        if ($len -ge 500 -and (-not $hasProblemFrame -or -not $hasNextStep)) {
            $fakePage = $true
        }

        $fakeShell = $false
        if (($pageType -eq "SCAFFOLD" -or $pageType -eq "EMPTY") -and $links -gt 0 -and $len -lt 350) {
            $fakeShell = $true
        }

        $out += [pscustomobject]@{
            path = $path
            title = $title
            len = $len
            img = $img
            links = $links
            visual = $visual
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

        $band = "ok"
        if ($len -lt 350) {
            $band = "bad"
        }
        elseif ($len -lt 700) {
            $band = "thin"
        }

        $out += [pscustomobject]@{
            path = $p
            weight = Get-Weight $p
            band = $band
            len = $len
            images = Get-Int $i.images
            links = Get-Int $i.links
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
        if ($s.path -eq "/hubs/" -and $s.band -eq "ok") { $router = $true }
        if ($s.path -eq "/search/" -and $s.band -eq "ok") { $flow = $true }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.path -eq "/" -and $f.has_value_statement -and $f.has_next_step) { $entry = $true }
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

    foreach ($f in (Normalize $findings)) {
        if ($f.path -eq "/") {
            if (-not $f.has_value_statement -or -not $f.has_next_step -or -not $f.has_cta) {
                $homepageFail = $true
                $entryClarityRoutes += $f.path
            }
        }

        if (-not $f.has_problem_frame -or -not $f.has_solution_depth) {
            $intentFailRoutes += $f.path
        }

        if ($f.fake_page) {
            $fakePageRoutes += $f.path
        }

        if ($f.fake_shell) {
            $fakeShellRoutes += $f.path
        }

        if (-not $f.has_next_step) {
            $deadEndRoutes += $f.path
        }

        if ($f.ui_contamination) {
            $uiContaminationRoutes += $f.path
        }

        if (-not $f.has_cta) {
            $ctaMissingRoutes += $f.path
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
    }
}

function Build-PageTypeAudit {
    param($findings)

    $out = @()
    foreach ($f in (Normalize $findings)) {
        $out += [pscustomobject]@{
            path = $f.path
            page_type = $f.page_type
            fake_shell = $f.fake_shell
            fake_page = $f.fake_page
            ui_contamination = $f.ui_contamination
            has_cta = $f.has_cta
            has_value_statement = $f.has_value_statement
            has_problem_frame = $f.has_problem_frame
            has_solution_depth = $f.has_solution_depth
            has_next_step = $f.has_next_step
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
        if ($s.weight -eq "critical" -and $s.band -ne "ok") {
            $criticalBad += $s.path
        }
    }

    foreach ($f in (Normalize $findings)) {
        if ($f.visual -eq "empty") {
            $visualEmpty += $f.path
        }
    }

    $failedGates = @()

    if (-not $repoAudit.repo_clean) { $failedGates += "REPO_CLEANLINESS" }
    if (-not $repoAudit.architecture_clean) { $failedGates += "ARCHITECTURE" }
    if (-not $sys.system_exists) { $failedGates += "SYSTEM" }
    if (-not $sys.entry_exists) { $failedGates += "ENTRY" }
    if (-not $sys.router_exists) { $failedGates += "ROUTER" }
    if (-not $sys.flow_exists) { $failedGates += "FLOW" }
    if (-not $sys.conversion_exists) { $failedGates += "CONVERSION" }
    if (-not $sys.visual_trust_exists) { $failedGates += "VISUAL" }
    if ($ux.homepage_fail) { $failedGates += "ENTRY_QUALITY" }
    if ($ux.intent_fail_routes.Count -gt 0) { $failedGates += "INTENT" }
    if ($ux.fake_page_routes.Count -gt 0) { $failedGates += "FAKE_PAGE" }
    if ($ux.fake_shell_routes.Count -gt 0) { $failedGates += "FAKE_SHELL" }
    if ($ux.dead_end_routes.Count -gt 0) { $failedGates += "FLOW_DEAD_END" }
    if ($ux.ui_contamination_routes.Count -gt 0) { $failedGates += "UI_CONTAMINATION" }
    if ($ux.cta_missing_routes.Count -gt 0) { $failedGates += "CTA_MISSING" }

    $core = "Site does not function as a decision system."

    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $core = "Repo is not a clean product boundary and mixes product with internal/dev artifacts."
    }
    elseif ($ux.ui_contamination_routes.Count -gt 0) {
        $core = "Public pages contain development or internal UI contamination."
    }
    elseif ($ux.homepage_fail) {
        $core = "Homepage does not function as a usable entry point."
    }
    elseif ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) {
        $core = "Some pages create an illusion of content but do not function as real product pages."
    }
    elseif (-not $sys.system_exists) {
        $core = "Site does not function as a decision system."
    }
    elseif ($criticalBad.Count -gt 0) {
        $core = "Critical routes lack sufficient depth and break navigation flow."
    }

    $p0 = @()
    if (-not $repoAudit.repo_clean) {
        $p0 += "Repo cleanliness failed: internal or build artifacts are present in the product repo."
    }
    if (-not $repoAudit.architecture_clean) {
        $p0 += "Architecture boundary failed: product content is mixed with scripts/tools/test layers."
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $p0 += "UI contamination detected on public pages (" + (Join-ListText $ux.ui_contamination_routes) + ")."
    }
    if ($ux.homepage_fail) {
        $p0 += "Homepage does not function as a usable entry point."
    }
    if (-not $sys.router_exists) {
        $p0 += "Router layer is missing or ineffective."
    }
    if (-not $sys.flow_exists) {
        $p0 += "Discovery flow is missing or ineffective."
    }
    if (-not $sys.conversion_exists) {
        $p0 += "Conversion layer is missing."
    }
    if (-not $sys.visual_trust_exists) {
        $p0 += "Visual trust layer is missing on key pages."
    }
    if ($ux.fake_shell_routes.Count -gt 0) {
        $p0 += "Empty shell or scaffold pages detected (" + (Join-ListText $ux.fake_shell_routes) + ")."
    }
    if ($ux.fake_page_routes.Count -gt 0) {
        $p0 += "Fake pages detected: pages look present but do not frame a problem or next step (" + (Join-ListText $ux.fake_page_routes) + ")."
    }
    if ($ux.dead_end_routes.Count -gt 0) {
        $p0 += "User flow breaks on dead-end pages (" + (Join-ListText $ux.dead_end_routes) + ")."
    }
    if ($ux.cta_missing_routes.Count -gt 0) {
        $p0 += "No clear CTA or next action detected on some routes (" + (Join-ListText $ux.cta_missing_routes) + ")."
    }
    if ($criticalBad.Count -gt 0) {
        $p0 += "Critical routes lack depth (" + (Join-ListText $criticalBad) + ")."
    }
    if ($visualEmpty.Count -gt 0) {
        $p0 += "Some key routes appear empty (" + (Join-ListText $visualEmpty) + ")."
    }
    $p0 = @($p0 | Select-Object -Unique | Select-Object -First 12)

    $p1 = @()
    if ($ux.intent_fail_routes.Count -gt 0) {
        $p1 += "Some pages do not clearly frame the user problem or use-case (" + (Join-ListText $ux.intent_fail_routes) + ")."
    }
    if ($criticalBad -contains "/hubs/") {
        $p1 += "Hubs behave like a thin page, not a real router."
    }
    if ($criticalBad -contains "/search/") {
        $p1 += "Search behaves like a thin utility page, not a discovery system."
    }
    if (-not $sys.conversion_exists) {
        $p1 += "No dedicated monetization or conversion route detected in the current structure."
    }
    $p1 = @($p1 | Select-Object -Unique | Select-Object -First 6)

    $do = @()
    if (-not $repoAudit.repo_clean -or -not $repoAudit.architecture_clean) {
        $do += "Separate product files from internal, batch, test, and governance artifacts in the repo."
    }
    if ($ux.ui_contamination_routes.Count -gt 0) {
        $do += "Remove development and internal UI contamination from public pages."
    }
    if ($ux.homepage_fail) {
        $do += "Rebuild homepage as entry point with value statement, route options, and CTA."
    }
    if (-not $sys.router_exists -or ($criticalBad -contains "/hubs/")) {
        $do += "Rebuild /hubs/ as an intent-based router, not a flat list."
    }
    if (-not $sys.flow_exists -or ($criticalBad -contains "/search/")) {
        $do += "Rebuild /search/ as a discovery flow with guidance and entry points."
    }
    if (-not $sys.conversion_exists) {
        $do += "Add a visible conversion layer on key pages."
    }
    if (-not $sys.visual_trust_exists) {
        $do += "Add visual trust blocks, previews, or screenshots on key pages."
    }
    if ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) {
        $do += "Replace fake pages and empty shells with real problem → solution → next-step structure."
    }
    $do = @($do | Select-Object -Unique | Select-Object -First 5)

    $readiness = [pscustomobject]@{
        indexing = "NO"
        traffic = "NO"
        monetization = "NO"
    }

    if ($sys.system_exists -and $sys.entry_exists -and $sys.router_exists -and $sys.flow_exists -and $repoAudit.repo_clean -and $repoAudit.architecture_clean -and $ux.ui_contamination_routes.Count -eq 0) {
        $readiness.indexing = "PARTIAL"
        $readiness.traffic = "PARTIAL"
    }

    if ($sys.conversion_exists) {
        $readiness.monetization = "PARTIAL"
    }

    $missing = @()
    if (-not $sys.router_exists) { $missing += "router_layer" }
    if (-not $sys.flow_exists) { $missing += "discovery_flow" }
    if (-not $sys.conversion_exists) { $missing += "conversion_layer" }
    if (-not $sys.visual_trust_exists) { $missing += "visual_trust_layer" }
    if (-not $sys.entry_exists) { $missing += "entry_structure" }
    if ($ux.fake_page_routes.Count -gt 0 -or $ux.fake_shell_routes.Count -gt 0) { $missing += "real_problem_solution_pages" }
    if ($ux.ui_contamination_routes.Count -gt 0) { $missing += "clean_public_ui" }
    if ($ux.cta_missing_routes.Count -gt 0) { $missing += "clear_cta_layer" }
    $missing = @($missing | Select-Object -Unique)

    return [pscustomobject]@{
        system_verdict = "FAIL"
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
    $lines += "SYSTEM VERDICT"
    $lines += $dec.system_verdict
    $lines += ""
    $lines += "FAILED GATES"
    foreach ($x in (Normalize $dec.failed_gates)) { $lines += "- $x" }
    $lines += ""
    $lines += "CORE"
    $lines += $dec.core
    $lines += ""
    $lines += "P0"
    foreach ($x in (Normalize $dec.p0)) { $lines += "- $x" }
    $lines += ""
    $lines += "P1"
    foreach ($x in (Normalize $dec.p1)) { $lines += "- $x" }
    $lines += ""
    $lines += "DO NEXT"
    $i = 1
    foreach ($x in (Normalize $dec.do)) {
        $lines += ("{0}. {1}" -f $i, $x)
        $i++
    }
    $lines += ""
    $lines += "READINESS"
    $lines += ("indexing: " + $dec.readiness.indexing)
    $lines += ("traffic: " + $dec.readiness.traffic)
    $lines += ("monetization: " + $dec.readiness.monetization)
    $lines += ""
    $lines += "MISSING COMPONENTS"
    foreach ($x in (Normalize $dec.missing_components)) { $lines += "- $x" }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SiteAuditor {
    param([string]$BaseUrl)

    $root = Get-ScriptRoot
    $rep = Join-Path $root "reports"
    if (-not (Test-Path $rep)) {
        New-Item -ItemType Directory -Path $rep | Out-Null
    }

    $repoRoot = Get-RepoRoot -StartPath $root
    $repoAudit = Analyze-RepoHygiene -RepoRoot $repoRoot

    $manifestPath = Join-Path $rep "visual_manifest.json"
    $manifest = Read-JsonFile -Path $manifestPath

    $items = Normalize $manifest
    $inventory = Build-RouteInventory -items $items
    $find = Get-Findings -items $items
    $scores = Get-Scores -items $items
    $pageTypeAudit = Build-PageTypeAudit -findings $find
    $dec = Decide -scores $scores -findings $find -repoAudit $repoAudit

    $inventory | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "route_inventory.json") -Encoding UTF8
    $find | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "visual_findings.json") -Encoding UTF8
    $scores | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "route_scores.json") -Encoding UTF8
    $pageTypeAudit | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "page_type_audit.json") -Encoding UTF8
    $repoAudit | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rep "repo_audit.json") -Encoding UTF8
    $dec | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $rep "decision_summary.json") -Encoding UTF8
    Write-DecisionText -Path (Join-Path $rep "REPORT.txt") -dec $dec

    Write-Host "DONE"
}
