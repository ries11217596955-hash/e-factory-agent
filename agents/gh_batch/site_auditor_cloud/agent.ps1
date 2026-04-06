param(
    [string]$Mode = "",
    [string]$TargetPath = "",
    [string]$ZipPath = "",
    [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    return (Get-Location).Path
}

function Ensure-Dir {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Save-Json {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-TextLength {
    param([string]$Path)
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return [string]$text
    }
    catch {
        return ""
    }
}

function Get-RelativePath {
    param([string]$Root,[string]$Path)
    $rootUri = New-Object System.Uri(((Resolve-Path $Root).Path.TrimEnd('\\','/')) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = New-Object System.Uri((Resolve-Path $Path).Path)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('/','/')
}

function Get-RepoFacts {
    param([string]$Root)

    $allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mdFiles = @($allFiles | Where-Object { $_.Extension -in @('.md','.njk','.html','.11ty.js','.json','.yml','.yaml','.js','.ts','.ps1') })
    $routeFiles = @(
        $allFiles |
        Where-Object {
            $_.FullName -match '[\\/](src|about|tools|news|posts|hubs|start-here|search)[\\/]' -and
            $_.Extension -in @('.md','.njk','.html')
        }
    )

    $routes = New-Object System.Collections.Generic.List[object]
    foreach ($file in $routeFiles) {
        $rel = Get-RelativePath -Root $Root -Path $file.FullName
        $text = Get-TextLength -Path $file.FullName
        $routes.Add([pscustomobject]@{
            relative_path = $rel
            text_length   = $text.Length
            empty         = ($text.Trim().Length -eq 0)
            has_cta       = ($text -match '(?i)(next step|use this tool|try|start here|learn more|cta|affiliate|tool)')
            has_problem   = ($text -match '(?i)(problem|pain|issue|what this fixes|why)')
            has_solution  = ($text -match '(?i)(solution|how to|steps|workflow|fix)')
        })
    }

    $suspiciousTop = @(
        Get-ChildItem -LiteralPath $Root -Force |
        Where-Object {
            $_.PSIsContainer -and $_.Name -match '^[0-9a-f]{3}$'
        } |
        Select-Object -ExpandProperty Name
    )

    $workflowFiles = @(
        $allFiles |
        Where-Object { $_.FullName -match '[\\/]\.github[\\/]workflows[\\/].+\.ya?ml$' } |
        ForEach-Object { Get-RelativePath -Root $Root -Path $_.FullName }
    )

    $repoFacts = [pscustomobject]@{
        repo_root = (Resolve-Path $Root).Path
        file_count = $allFiles.Count
        markdown_like_count = $mdFiles.Count
        route_file_count = $routeFiles.Count
        suspicious_top_level_dirs = $suspiciousTop
        suspicious_top_level_count = @($suspiciousTop).Count
        workflow_files = $workflowFiles
        workflow_count = @($workflowFiles).Count
        routes = $routes
    }

    return $repoFacts
}

function Get-PageVerdicts {
    param($Routes)
    $verdicts = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($Routes)) {
        $state = "OK"
        if ($r.empty) { $state = "EMPTY" }
        elseif ($r.text_length -lt 150) { $state = "THIN" }
        elseif (-not $r.has_problem -or -not $r.has_solution) { $state = "WEAK" }

        $verdicts.Add([pscustomobject]@{
            relative_path = $r.relative_path
            state = $state
            text_length = $r.text_length
            has_problem = $r.has_problem
            has_solution = $r.has_solution
            has_cta = $r.has_cta
        })
    }
    return $verdicts
}

function Get-Decision {
    param(
        [string]$Mode,
        $RepoFacts,
        $PageVerdicts,
        [bool]$CaptureOk,
        [int]$ScreenshotCount
    )

    $p0 = New-Object System.Collections.Generic.List[string]
    $p1 = New-Object System.Collections.Generic.List[string]
    $do = New-Object System.Collections.Generic.List[string]

    $empty = @($PageVerdicts | Where-Object { $_.state -eq 'EMPTY' })
    $thin = @($PageVerdicts | Where-Object { $_.state -eq 'THIN' })
    $weak = @($PageVerdicts | Where-Object { $_.state -eq 'WEAK' })

    if ($RepoFacts.suspicious_top_level_count -gt 0) {
        $p0.Add("Suspicious top-level dirs in audit source: " + ($RepoFacts.suspicious_top_level_dirs -join ', '))
        $do.Add("Clean stray top-level dirs from audit source before trusting repo structure")
    }

    if ($empty.Count -gt 0) {
        $p0.Add("Empty route files detected: " + (($empty | Select-Object -First 3 -ExpandProperty relative_path) -join ', '))
        $do.Add("Fill empty route files with real content blocks")
    }

    if ($thin.Count -gt 0) {
        $p1.Add("Thin route files detected: " + (($thin | Select-Object -First 3 -ExpandProperty relative_path) -join ', '))
    }

    if ($weak.Count -gt 0) {
        $p1.Add("Weak route files without full problem/solution pattern: " + (($weak | Select-Object -First 3 -ExpandProperty relative_path) -join ', '))
    }

    if ($Mode -eq 'REPO' -and -not $CaptureOk) {
        $p1.Add("Live screenshot layer missing or failed")
        $do.Add("Restore capture layer for live visual truth")
    }

    if ($Mode -eq 'ZIP') {
        $do.Add("Route processed ZIP to done/failed after audit")
    }

    $core = ""
    switch ($Mode) {
        'ZIP'  { $core = "ZIP audit now runs on extracted ZIP content, not on the live site." }
        'REPO' { $core = "Manual audit now runs on repo content, with live screenshots as optional side evidence." }
        default { $core = "Audit completed." }
    }

    return [pscustomobject]@{
        core = $core
        p0 = @($p0 | Select-Object -First 3)
        p1 = @($p1 | Select-Object -First 3)
        do = @($do | Select-Object -First 3)
        empty_count = $empty.Count
        thin_count = $thin.Count
        weak_count = $weak.Count
        screenshot_count = $ScreenshotCount
    }
}

function Write-Report {
    param(
        [string]$Path,
        [string]$Mode,
        [string]$SourceRoot,
        [string]$ZipPath,
        [string]$BaseUrl,
        $Decision,
        $RepoFacts
    )

    $lines = @()
    $lines += "MODE:"
    $lines += $Mode
    $lines += ""
    $lines += "SOURCE:"
    $lines += "Root: $SourceRoot"
    if (-not [string]::IsNullOrWhiteSpace($ZipPath)) { $lines += "ZIP: $ZipPath" }
    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) { $lines += "BASE_URL: $BaseUrl" }
    $lines += ""
    $lines += "CORE PROBLEM:"
    $lines += [string]$Decision.core
    $lines += ""
    $lines += "P0:"
    if (@($Decision.p0).Count -eq 0) { $lines += "- none" } else { @($Decision.p0) | ForEach-Object { $lines += "- $_" } }
    $lines += ""
    $lines += "P1:"
    if (@($Decision.p1).Count -eq 0) { $lines += "- none" } else { @($Decision.p1) | ForEach-Object { $lines += "- $_" } }
    $lines += ""
    $lines += "SUMMARY:"
    $lines += "- files: $($RepoFacts.file_count)"
    $lines += "- route files: $($RepoFacts.route_file_count)"
    $lines += "- suspicious top-level dirs: $($RepoFacts.suspicious_top_level_count)"
    $lines += "- screenshots: $($Decision.screenshot_count)"
    $lines += "- empty routes: $($Decision.empty_count)"
    $lines += "- thin routes: $($Decision.thin_count)"
    $lines += "- weak routes: $($Decision.weak_count)"
    $lines += ""
    $lines += "DO NEXT:"
    if (@($Decision.do).Count -eq 0) {
        $lines += "1. Review JSON artifacts"
    }
    else {
        $i = 1
        foreach ($step in @($Decision.do)) {
            $lines += "${i}. $step"
            $i++
        }
    }

    [System.IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Capture {
    param(
        [string]$Root,
        [string]$BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = "BASE_URL_EMPTY" }
    }

    $packageJson = Join-Path $Root "package.json"
    $captureScript = Join-Path $Root "capture.mjs"
    if (!(Test-Path $packageJson) -or !(Test-Path $captureScript)) {
        return [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = "CAPTURE_FILES_MISSING" }
    }

    $env:SITE_AUDITOR_BASE_URL = $BaseUrl

    try {
        Push-Location $Root
        & node $captureScript
        $code = $LASTEXITCODE
        Pop-Location

        if ($code -ne 0) {
            return [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = "CAPTURE_EXIT_$code" }
        }

        $manifestPath = Join-Path $Root "reports/visual_manifest.json"
        if (!(Test-Path $manifestPath)) {
            return [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = "MANIFEST_MISSING" }
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $count = 0
        foreach ($item in @($manifest)) {
            try { $count += [int]$item.screenshotCount } catch {}
        }

        return [pscustomobject]@{ ok = $true; screenshot_count = $count; reason = "OK" }
    }
    catch {
        try { Pop-Location } catch {}
        return [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = $_.Exception.Message }
    }
}

function Write-DoneMarker {
    param([string]$Path,[string]$Status,[string]$Reason)
    [System.IO.File]::WriteAllText($Path, "status=$Status`nreason=$Reason`n", [System.Text.UTF8Encoding]::new($false))
}

$Root = Get-ScriptRoot
$Reports = Join-Path $Root "reports"
$Outbox = Join-Path $Root "outbox"
Ensure-Dir $Reports
Ensure-Dir $Outbox

if ([string]::IsNullOrWhiteSpace($Mode)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FORCE_MODE)) { $Mode = [string]$env:FORCE_MODE } else { $Mode = "REPO" }
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = $Root
}

if (!(Test-Path -LiteralPath $TargetPath)) {
    $msg = "TargetPath not found: $TargetPath"
    Write-Error $msg
    Write-DoneMarker -Path (Join-Path $Reports "DONE.fail") -Status "FAIL" -Reason $msg
    exit 1
}

$resolvedTarget = (Resolve-Path $TargetPath).Path

Remove-Item (Join-Path $Reports "DONE.ok") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Reports "DONE.fail") -Force -ErrorAction SilentlyContinue

$repoFacts = Get-RepoFacts -Root $resolvedTarget
$pageVerdicts = Get-PageVerdicts -Routes $repoFacts.routes

$capture = [pscustomobject]@{ ok = $false; screenshot_count = 0; reason = "SKIPPED" }
if ($Mode -eq "REPO" -and -not [string]::IsNullOrWhiteSpace($BaseUrl)) {
    $capture = Invoke-Capture -Root $Root -BaseUrl $BaseUrl
}

$decision = Get-Decision -Mode $Mode -RepoFacts $repoFacts -PageVerdicts $pageVerdicts -CaptureOk $capture.ok -ScreenshotCount $capture.screenshot_count

$repoAudit = [pscustomobject]@{
    mode = $Mode
    repo_bound = $true
    target_root = $resolvedTarget
    zip_path = $ZipPath
    base_url = $BaseUrl
    capture = $capture
    notes = @(
        "ZIP mode audits extracted ZIP content.",
        "REPO mode audits repo filesystem content.",
        "Live capture is optional side evidence and does not replace repo/zip truth."
    )
}

Save-Json -Path (Join-Path $Reports "repo_audit.json") -Object $repoAudit
Save-Json -Path (Join-Path $Reports "route_inventory.json") -Object $repoFacts.routes
Save-Json -Path (Join-Path $Reports "page_type_audit.json") -Object $pageVerdicts
Save-Json -Path (Join-Path $Reports "audit_result.json") -Object ([pscustomobject]@{
    mode = $Mode
    source_root = $resolvedTarget
    repo_facts = $repoFacts
    page_verdicts = $pageVerdicts
    decision = $decision
})
Save-Json -Path (Join-Path $Reports "HOW_TO_FIX.json") -Object ([pscustomobject]@{
    mode = $Mode
    do_next = $decision.do
    p0 = $decision.p0
    p1 = $decision.p1
})

Write-Report -Path (Join-Path $Reports "REPORT.txt") -Mode $Mode -SourceRoot $resolvedTarget -ZipPath $ZipPath -BaseUrl $BaseUrl -Decision $decision -RepoFacts $repoFacts

$summaryText = @(
    "MODE: $Mode",
    "CORE: $($decision.core)",
    "P0: " + ($(if(@($decision.p0).Count){@($decision.p0) -join ' | '}else{'none'}))
)
[System.IO.File]::WriteAllText((Join-Path $Reports "11A_EXECUTIVE_SUMMARY.txt"), ($summaryText -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $Reports "00_PRIORITY_ACTIONS.txt"), ((@($decision.do) | ForEach-Object { "- $_" }) -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $Reports "01_TOP_ISSUES.txt"), ((@($decision.p0 + $decision.p1) | ForEach-Object { "- $_" }) -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

Write-DoneMarker -Path (Join-Path $Reports "DONE.ok") -Status "OK" -Reason "AUDIT_COMPLETE"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outZip = Join-Path $Outbox ("site_audit_" + $Mode.ToLowerInvariant() + "_" + $stamp + ".zip")
if (Test-Path $outZip) { Remove-Item $outZip -Force }
Compress-Archive -Path (Join-Path $Reports "*") -DestinationPath $outZip -Force

Write-Host ("AUDIT COMPLETE: mode={0}; source={1}; screenshots={2}" -f $Mode, $resolvedTarget, $capture.screenshot_count)
exit 0
