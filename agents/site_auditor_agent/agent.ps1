function Get-AgentRoot {
    $root = $PSScriptRoot
    if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return $root
}

function Get-AgentConfig {
    param([string]$ConfigPath)

    if (!(Test-Path -LiteralPath $ConfigPath)) { throw "CONFIG_NOT_FOUND: $ConfigPath" }
    $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "CONFIG_EMPTY: $ConfigPath" }

    try { return ($raw | ConvertFrom-Json) }
    catch { throw "CONFIG_JSON_INVALID: $ConfigPath" }
}

function Get-GitHubToken {
    param([string]$TokenPath)

    if (!(Test-Path -LiteralPath $TokenPath)) { throw "TOKEN_FILE_NOT_FOUND: $TokenPath" }
    $token = (Get-Content -LiteralPath $TokenPath -Raw -Encoding UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) { throw "TOKEN_EMPTY" }
    return $token
}

function Remove-DirectorySafe {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host "[WARN] REMOVE_PATH_FAILED: $Path :: $($_.Exception.Message)"
        }
    }
}

function Expand-RepoZipToTarget {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [string]$ExtractRoot,
        [string]$TargetPath,
        [string]$TargetDir
    )

    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        $TargetDir = $TargetPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExtractRoot)) {
        $TargetDir = $ExtractRoot
    }

    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        throw "NO_TARGET_PATH_PROVIDED"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $TargetDir) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

        $wrapperPrefix = $null
        foreach ($entry in $zip.Entries) {
            $full = $entry.FullName
            if ([string]::IsNullOrWhiteSpace($full)) { continue }
            $parts = @($full -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if (@($parts).Count -ge 2) {
                $wrapperPrefix = $parts[0]
                break
            }
        }

        foreach ($entry in $zip.Entries) {
            $full = $entry.FullName
            if ([string]::IsNullOrWhiteSpace($full)) { continue }

            $normalized = $full -replace '/', '\'
            $normalized = $normalized.TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

            $relativePath = $normalized

            if (-not [string]::IsNullOrWhiteSpace($wrapperPrefix)) {
                $wrapperPath = ($wrapperPrefix -replace '/', '\').Trim('\')
                if ($relativePath -ieq $wrapperPath) { continue }
                if ($relativePath.ToLowerInvariant().StartsWith(($wrapperPath + '\').ToLowerInvariant())) {
                    $relativePath = $relativePath.Substring($wrapperPath.Length + 1)
                }
            }

            $relativePath = $relativePath.TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

            $destinationPath = Join-Path $TargetDir $relativePath
            $destinationDir = Split-Path -Parent $destinationPath

            if (-not [string]::IsNullOrWhiteSpace($destinationDir) -and !(Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            if ([string]::IsNullOrWhiteSpace($entry.Name)) {
                if (!(Test-Path -LiteralPath $destinationPath)) {
                    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                }
                continue
            }

            try {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationPath, $true)
            }
            catch {
                throw "ZIP_EXTRACT_FAIL_SAFE | ZIP_ENTRY_EXTRACT_FAILED: $($entry.FullName) => $destinationPath :: $($_.Exception.Message)"
            }
        }
    }
    finally {
        if ($null -ne $zip) {
            $zip.Dispose()
        }
    }

    if (!(Test-Path -LiteralPath $TargetDir)) {
        throw "REPO_ROOT_NOT_CREATED: $TargetDir"
    }

    $repoFiles = @(Get-ChildItem -LiteralPath $TargetDir -Recurse -File -ErrorAction SilentlyContinue)
    if ($repoFiles.Count -eq 0) {
        throw "REPO_ROOT_EMPTY: $TargetDir"
    }

    if (!(Test-Path -LiteralPath (Join-Path $TargetDir "src"))) {
        throw "REPO_SRC_ROOT_MISSING: $TargetDir"
    }
}

function Download-RepoZipViaApi {
    param(
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$Branch,
        [string]$Token,
        [string]$WorkPath,
        [string]$TargetPath
    )

    $zipUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/zipball/$Branch"
    $zipPath = Join-Path $WorkPath "repo.zip"
    $extractPath = Join-Path $WorkPath "x"

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    $headers = @{
        Authorization = "Bearer $Token"
        Accept        = "application/vnd.github+json"
        "User-Agent"  = "SITE_AUDITOR_AGENT"
    }

    try {
        Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zipPath -UseBasicParsing
    }
    catch {
        throw "GITHUB_ZIP_DOWNLOAD_FAILED: $zipUrl :: $($_.Exception.Message)"
    }

    if (!(Test-Path -LiteralPath $zipPath)) { throw "ZIP_NOT_DOWNLOADED" }

    Expand-RepoZipToTarget -ZipPath $zipPath -ExtractRoot $extractPath -TargetPath $TargetPath
}

function Write-TextSummary {
    param(
        [string]$ReportDir,
        [object]$Inventory,
        [object]$SemanticIssues,
        [object]$LinkIssues,
        [object]$Orphans,
        [object]$RenderAudit,
        [object]$Screenshots,
        [object]$TargetAlignment,
        [object]$StageAssessment
    )

    $publishableCount = @($Inventory | Where-Object { $_.is_publishable }).Count
    $missingRoutes = @($TargetAlignment.missing_required_routes)
    $renderFails = @($RenderAudit | Where-Object { $_.status -ne 'OK' }).Count

    $summaryObj = [PSCustomObject]@{
        publishable_pages = $publishableCount
        inventory_count = @($Inventory).Count
        semantic_issues = @($SemanticIssues).Count
        broken_links = @($LinkIssues).Count
        orphan_pages = @($Orphans).Count
        render_failures = $renderFails
        screenshots = @($Screenshots | Where-Object { $_.status -eq 'OK' }).Count
        build_stage = $StageAssessment.build_stage
        target_coverage_percent = $TargetAlignment.required_route_coverage_percent
        missing_required_routes = $missingRoutes
        critical_blockers = @($StageAssessment.critical_blockers).Count
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $summaryObj | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $ReportDir "00_SUMMARY.json") -Encoding utf8

    $lines = @()
    $lines += "SITE AUDIT SUMMARY"
    $lines += ""
    $lines += "Build Stage           : $($StageAssessment.build_stage)"
    $lines += "Target Coverage       : $($TargetAlignment.required_route_coverage_percent)%"
    $lines += "Publishable Pages     : $publishableCount"
    $lines += "Inventory Count       : $(@($Inventory).Count)"
    $lines += "Semantic Issues       : $(@($SemanticIssues).Count)"
    $lines += "Broken Links          : $(@($LinkIssues).Count)"
    $lines += "Orphan Pages          : $(@($Orphans).Count)"
    $lines += "Render Failures       : $renderFails"
    $lines += "Screenshots OK        : $(@($Screenshots | Where-Object { $_.status -eq 'OK' }).Count)"
    $lines += "Critical Blockers     : $(@($StageAssessment.critical_blockers).Count)"
    $lines += ""
    $lines += "Missing Required Routes:"
    if (@($missingRoutes).Count -eq 0) {
        $lines += "- none"
    } else {
        foreach ($r in $missingRoutes) { $lines += "- $r" }
    }

    $lines += ""
    $lines += "Top Critical Blockers:"
    if (@($StageAssessment.critical_blockers).Count -eq 0) {
        $lines += "- none"
    } else {
        foreach ($b in @($StageAssessment.critical_blockers | Select-Object -First 15)) {
            $routeValue = $null
            try { $routeValue = $b.route } catch {}
            $routeText = if ($routeValue) { " :: $routeValue" } else { "" }
            $lines += "- $($b.type)$routeText"
        }
    }

    $lines | Out-File -LiteralPath (Join-Path $ReportDir "00_SUMMARY.txt") -Encoding utf8
}

function Invoke-SiteAudit {
    $AgentRoot = Get-AgentRoot
    $ConfigPath = Join-Path $AgentRoot "agent.config.json"
    $TargetPath = Join-Path $AgentRoot "site.target.json"
    $TokenPath  = Join-Path $AgentRoot ".state\github_token.txt"
    $OutboxPath = Join-Path $AgentRoot "outbox"
    $WorkPath   = Join-Path $OutboxPath ".work"

    New-Item -ItemType Directory -Force -Path $OutboxPath | Out-Null
    New-Item -ItemType Directory -Force -Path $WorkPath | Out-Null

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportDir = Join-Path $WorkPath "report_$ts"
    Remove-DirectorySafe -Path $reportDir
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

    try {
        Write-Host "[PHASE] Loading config"
        $cfg = Get-AgentConfig -ConfigPath $ConfigPath

        Write-Host "[PHASE] Loading target model"
        . "$AgentRoot\target_stage.ps1"
        $target = Get-TargetModel -TargetPath $TargetPath

        Write-Host "[PHASE] Resolving token"
        $token = Get-GitHubToken -TokenPath $TokenPath

        Write-Host "[PHASE] Loading modules"
        . "$AgentRoot\inventory.ps1"
        . "$AgentRoot\semantic_audit.ps1"
        . "$AgentRoot\links_audit.ps1"
        . "$AgentRoot\render_audit.ps1"
        . "$AgentRoot\screenshot.ps1"
        . "$AgentRoot\advice_engine.ps1"

        $repoOwner = $cfg.repo_owner
        $repoName  = $cfg.repo_name
        $branch    = $cfg.branch
        if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "main" }

        $baseUrl = $cfg.base_url
        if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = "https://automation-kb.pages.dev" }

        Write-Host "[PHASE] Fetching repository"
        $RepoPath = Join-Path $WorkPath "repo"
        Download-RepoZipViaApi -RepoOwner $repoOwner -RepoName $repoName -Branch $branch -Token $token -WorkPath $WorkPath -TargetPath $RepoPath

        if (!(Test-Path -LiteralPath $RepoPath)) { throw "REPO_ROOT_MISSING_AFTER_FETCH: $RepoPath" }
        $repoFileCount = @(Get-ChildItem -LiteralPath $RepoPath -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($repoFileCount -eq 0) { throw "REPO_ROOT_EMPTY_AFTER_FETCH: $RepoPath" }

        Write-Host "[PHASE] Building inventory"
        $Inventory = Build-SiteInventory -RepoPath $RepoPath -BaseUrl $baseUrl -Config $cfg

        # Persist inventory immediately, before any hard-fail.
        $inventoryPath = Join-Path $reportDir "01_INVENTORY.json"
        $Inventory | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $inventoryPath -Encoding utf8
        if (!(Test-Path -LiteralPath $inventoryPath)) { throw "INVENTORY_FILE_NOT_CREATED" }

        $publishableCheck = @($Inventory | Where-Object { $_.is_publishable }).Count
        $inventoryDebug = [PSCustomObject]@{
            inventory_total = @($Inventory).Count
            publishable_pages = $publishableCheck
            repo_path = $RepoPath
            report_dir = $reportDir
            sample_routes = @($Inventory | Select-Object -First 20 -ExpandProperty route)
            sample_publishable = @($Inventory | Select-Object -First 20 | ForEach-Object {
                [PSCustomObject]@{
                    file = $_.file
                    route = $_.route
                    is_publishable = $_.is_publishable
                    content_role = $_.content_role
                    page_type = $_.page_type
                }
            })
        }
        $inventoryDebug | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "01A_INVENTORY_DEBUG.json") -Encoding utf8

        Write-Host "[PHASE] Semantic audit"
        $SemanticIssues = Invoke-SemanticAudit -Inventory $Inventory
        $SemanticIssues | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "02_SEMANTIC_ISSUES.json") -Encoding utf8

        Write-Host "[PHASE] Links audit"
        $LinkAudit = Invoke-LinksAudit -Inventory $Inventory
        $LinkIssues = $LinkAudit.BrokenLinks
        $Orphans = $LinkAudit.Orphans
        $NavGraph = $LinkAudit.NavGraph
        $LinkIssues | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "03_BROKEN_LINKS.json") -Encoding utf8
        $Orphans | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "04_ORPHAN_PAGES.json") -Encoding utf8
        $NavGraph | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "05_NAV_GRAPH.json") -Encoding utf8

        Write-Host "[PHASE] Render audit"
        $RenderAudit = Invoke-RenderAudit -Inventory $Inventory -Config $cfg
        $RenderAudit | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "06_RENDER_AUDIT.json") -Encoding utf8

        Write-Host "[PHASE] Stage assessment"
        $TargetStage = Invoke-TargetStageAudit -Inventory $Inventory -SemanticIssues $SemanticIssues -LinkIssues $LinkIssues -RenderAudit $RenderAudit -Target $target
        $TargetAlignment = $TargetStage.TargetAlignment
        $StageAssessment = $TargetStage.StageAssessment
        $TargetAlignment | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "08_TARGET_ALIGNMENT.json") -Encoding utf8
        $StageAssessment | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "09_STAGE_ASSESSMENT.json") -Encoding utf8

        Write-Host "[PHASE] Screenshots"
        $Screenshots = Invoke-ScreenshotCapture -Inventory $Inventory -RenderAudit $RenderAudit -WorkPath $WorkPath -MaxScreenshots $cfg.max_screenshots
        $Screenshots | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "07_SCREENSHOTS.json") -Encoding utf8

        $metrics = [PSCustomObject]@{
            inventory_total = @($Inventory).Count
            publishable_pages = $publishableCheck
            semantic_issues = @($SemanticIssues).Count
            broken_links = @($LinkIssues).Count
            orphan_pages = @($Orphans).Count
            render_failures = @($RenderAudit | Where-Object { $_.status -ne 'OK' }).Count
            screenshot_ok = @($Screenshots | Where-Object { $_.status -eq 'OK' }).Count
        }
        $metrics | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "10_METRICS.json") -Encoding utf8

        # Hard-fails only after raw artifacts are persisted.
        if (@($Inventory).Count -eq 0) { throw "INVENTORY_EMPTY_HARD_FAIL" }
        if ($publishableCheck -eq 0) { throw "PUBLISHABLE_ZERO_HARD_FAIL" }

        Write-Host "[PHASE] Advice engine"
        Invoke-AdviceEngine -ReportDir $reportDir -TargetConfigPath $TargetPath

        if (@($Screenshots).Count -gt 0) {
            $shotsDir = Join-Path $reportDir "screens"
            New-Item -ItemType Directory -Path $shotsDir -Force | Out-Null
            foreach ($shot in $Screenshots) {
                if ($shot.local_path -and (Test-Path -LiteralPath $shot.local_path)) {
                    Copy-Item -LiteralPath $shot.local_path -Destination (Join-Path $shotsDir ([IO.Path]::GetFileName($shot.local_path))) -Force
                }
            }
        }

        Write-TextSummary -ReportDir $reportDir -Inventory $Inventory -SemanticIssues $SemanticIssues -LinkIssues $LinkIssues -Orphans $Orphans -RenderAudit $RenderAudit -Screenshots $Screenshots -TargetAlignment $TargetAlignment -StageAssessment $StageAssessment
    }
    catch {
        $failureObj = [PSCustomObject]@{
            error = $_.Exception.Message
            script_stack = $_.ScriptStackTrace
            report_dir = $reportDir
            generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $failureObj | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $reportDir "RUN_FAILURE.json") -Encoding utf8
        throw
    }
    finally {
        $zip = Join-Path $OutboxPath "SITE_AUDIT_PACK_$ts.zip"
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        if (Test-Path -LiteralPath $reportDir) {
            Compress-Archive -Path (Join-Path $reportDir "*") -DestinationPath $zip -Force
            Write-Host ""
            Write-Host "REPORT:"
            Write-Host $zip
        }
    }
}
