param(
    [string]$MODE = 'REPO'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = $env:GITHUB_WORKSPACE
if (-not [string]::IsNullOrWhiteSpace($workspace)) {
    $base = Join-Path $workspace 'agents/gh_batch/site_auditor_cloud'
}
else {
    $base = $PSScriptRoot
}

Write-Host "OUTPUT BASE: $base"

$outboxDir = Join-Path $base 'outbox'
$reportsDir = Join-Path $base 'reports'
$runtimeDir = Join-Path $base 'runtime'
$zipWorkRoot = Join-Path $runtimeDir 'zip_extracted'
$timestamp = (Get-Date).ToString('o')
$status = 'FAIL'
$failureReason = $null
$global:AuditError = $null
$reportFiles = New-Object System.Collections.Generic.List[string]

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Reset-Dir([string]$Path) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    $Data | ConvertTo-Json -Depth 20 | Out-File -FilePath $Path -Encoding utf8
}

function Write-TextFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $Lines -join "`n" | Out-File -FilePath $Path -Encoding utf8
}

function New-SourceLayer {
    param([hashtable]$Overrides = @{})

    $sourceLayer = @{
        enabled = $false
        required = $false
        kind = $null
        root = $null
        extracted_root = $null
        base_url = $null
        summary = @{}
        findings = @()
        ok = $false
    }

    foreach ($key in @($Overrides.Keys)) {
        $sourceLayer[$key] = $Overrides[$key]
    }

    return $sourceLayer
}

function New-LiveLayer {
    param([hashtable]$Overrides = @{})

    $layer = @{
        enabled = $false
        required = $false
        root = $null
        base_url = $null
        summary = @{}
        findings = @()
        warnings = @()
        ok = $false
    }

    foreach ($key in @($Overrides.Keys)) {
        $layer[$key] = $Overrides[$key]
    }

    return $layer
}

function Safe-Get {
    param(
        [object]$Object,
        [string]$Key,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try {
            if ($Object.Contains($Key)) {
                return $Object[$Key]
            }
        }
        catch {
            try {
                if ($Object.Keys -contains $Key) {
                    return $Object[$Key]
                }
            }
            catch {
                return $Default
            }
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Key]
    if ($null -ne $property) {
        return $property.Value
    }

    return $Default
}

function Convert-ToIntSafe {
    param(
        [object]$Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Convert-ToBoolSafe {
    param(
        [object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    $normalized = $text.Trim().ToLowerInvariant()
    if ($normalized -in @('true', '1', 'yes', 'y')) { return $true }
    if ($normalized -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function Convert-ToObjectArraySafe {
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        return @($Value)
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value)
    }
    return @($Value)
}

function Convert-ToStringArraySafe {
    param(
        [object]$Value
    )

    $items = Convert-ToObjectArraySafe -Value $Value
    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($items)) {
        if ($null -eq $item) { continue }

        if ($item -is [System.Collections.IDictionary] -or $item -is [PSCustomObject]) {
            $json = $item | ConvertTo-Json -Depth 8 -Compress
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $normalized.Add([string]$json)
            }
            continue
        }

        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $normalized.Add($text)
        }
    }

    return @($normalized)
}

function Resolve-ManifestRoutes {
    param([object]$ManifestData)

    if ($null -eq $ManifestData) { return @() }

    if ($ManifestData -is [System.Collections.IDictionary] -or $ManifestData -is [PSCustomObject]) {
        $explicitRoutes = Safe-Get -Object $ManifestData -Key 'routes' -Default $null
        if ($null -ne $explicitRoutes) {
            if ($explicitRoutes -is [System.Collections.IDictionary]) {
                $mappedRoutes = New-Object System.Collections.Generic.List[object]
                foreach ($entryKey in @($explicitRoutes.Keys)) {
                    $entryValue = $explicitRoutes[$entryKey]
                    if ($null -eq $entryValue) { continue }
                    if ($entryValue -is [System.Collections.IDictionary] -or $entryValue -is [PSCustomObject]) {
                        $hasPath =
                            ($null -ne (Safe-Get -Object $entryValue -Key 'route_path' -Default $null)) -or
                            ($null -ne (Safe-Get -Object $entryValue -Key 'url' -Default $null))
                        if ($hasPath) {
                            $mappedRoutes.Add($entryValue)
                        }
                        else {
                            $mappedRoutes.Add([ordered]@{
                                    route_path = [string]$entryKey
                                    status = (Safe-Get -Object $entryValue -Key 'status' -Default 'unknown')
                                    screenshotCount = (Safe-Get -Object $entryValue -Key 'screenshotCount' -Default 0)
                                    bodyTextLength = (Safe-Get -Object $entryValue -Key 'bodyTextLength' -Default 0)
                                    links = (Safe-Get -Object $entryValue -Key 'links' -Default 0)
                                    images = (Safe-Get -Object $entryValue -Key 'images' -Default 0)
                                    title = (Safe-Get -Object $entryValue -Key 'title' -Default '')
                                    h1Count = (Safe-Get -Object $entryValue -Key 'h1Count' -Default 0)
                                    buttonCount = (Safe-Get -Object $entryValue -Key 'buttonCount' -Default 0)
                                    hasMain = (Safe-Get -Object $entryValue -Key 'hasMain' -Default $false)
                                    hasArticle = (Safe-Get -Object $entryValue -Key 'hasArticle' -Default $false)
                                    hasNav = (Safe-Get -Object $entryValue -Key 'hasNav' -Default $false)
                                    hasFooter = (Safe-Get -Object $entryValue -Key 'hasFooter' -Default $false)
                                    visibleTextSample = (Safe-Get -Object $entryValue -Key 'visibleTextSample' -Default '')
                                    contaminationFlags = (Safe-Get -Object $entryValue -Key 'contaminationFlags' -Default @())
                                })
                        }
                    }
                }

                if ($mappedRoutes.Count -gt 0) {
                    return @($mappedRoutes)
                }
            }

            return @(Convert-ToObjectArraySafe -Value $explicitRoutes)
        }

        $hasRouteShape =
            ($null -ne (Safe-Get -Object $ManifestData -Key 'route_path' -Default $null)) -or
            ($null -ne (Safe-Get -Object $ManifestData -Key 'url' -Default $null)) -or
            ($null -ne (Safe-Get -Object $ManifestData -Key 'status' -Default $null))

        if ($hasRouteShape) {
            return @($ManifestData)
        }

        return @()
    }

    if ($ManifestData -is [System.Collections.IEnumerable] -and -not ($ManifestData -is [string])) {
        return @($ManifestData)
    }

    return @(Convert-ToObjectArraySafe -Value $ManifestData)
}

function Normalize-LiveRoutes {
    param([object]$ManifestData)

    $rawRoutes = @(Resolve-ManifestRoutes -ManifestData $ManifestData)

    $normalized = New-Object System.Collections.Generic.List[object]
    $shapeWarnings = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt @($rawRoutes).Count; $index++) {
        $route = $rawRoutes[$index]
        if ($null -eq $route) {
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped null route entry at index $index.")
            continue
        }

        if (-not ($route -is [System.Collections.IDictionary] -or $route -is [PSCustomObject])) {
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped non-object route entry at index $index of type $($route.GetType().FullName).")
            continue
        }

        try {
            $routePathRaw = Safe-Get -Object $route -Key 'route_path' -Default (Safe-Get -Object $route -Key 'routePath' -Default '')
            if ([string]::IsNullOrWhiteSpace([string]$routePathRaw)) {
                $routePathRaw = Safe-Get -Object $route -Key 'url' -Default ''
            }
            $routePath = [string]$routePathRaw
            if ([string]::IsNullOrWhiteSpace($routePath)) {
                $routePath = "/unnamed-route-$index"
                $shapeWarnings.Add("ROUTE_NORMALIZATION: route index $index had no route_path/url; generated synthetic path $routePath.")
            }

            $statusValue = Safe-Get -Object $route -Key 'status' -Default 'error'
            $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
            $normalizedStatus = if ($statusCode -ge 0) { $statusCode } else { [string]$statusValue }

            $flags = Convert-ToStringArraySafe -Value (Safe-Get -Object $route -Key 'contaminationFlags' -Default @())

            $normalized.Add([ordered]@{
                    route_path = $routePath
                    status = $normalizedStatus
                    screenshotCount = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'screenshotCount' -Default 0) -Default 0
                    bodyTextLength = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'bodyTextLength' -Default 0) -Default 0
                    links = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'links' -Default 0) -Default 0
                    images = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'images' -Default 0) -Default 0
                    title = [string](Safe-Get -Object $route -Key 'title' -Default '')
                    h1Count = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'h1Count' -Default 0) -Default 0
                    buttonCount = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'buttonCount' -Default 0) -Default 0
                    hasMain = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasMain' -Default $false) -Default $false
                    hasArticle = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasArticle' -Default $false) -Default $false
                    hasNav = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasNav' -Default $false) -Default $false
                    hasFooter = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasFooter' -Default $false) -Default $false
                    visibleTextSample = [string](Safe-Get -Object $route -Key 'visibleTextSample' -Default '')
                    contaminationFlags = @($flags)
                })
        }
        catch {
            $routeError = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($routeError)) { $routeError = 'Unknown route normalization error.' }
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped route index $index due to normalization error: $routeError")
            continue
        }
    }

    return @{
        routes = @($normalized)
        raw_count = @($rawRoutes).Count
        dropped_count = [int]([Math]::Max(0, @($rawRoutes).Count - $normalized.Count))
        warnings = @($shapeWarnings)
    }
}

function Normalize-AuditResult {
    param([hashtable]$AuditResult)

    if ($null -eq $AuditResult) {
        $AuditResult = @{}
    }

    $AuditResult.source = New-SourceLayer -Overrides (Safe-Get -Object $AuditResult -Key 'source' -Default @{})
    $AuditResult.live = New-LiveLayer -Overrides (Safe-Get -Object $AuditResult -Key 'live' -Default @{})

    if (-not $AuditResult.ContainsKey('required_inputs') -or $null -eq $AuditResult.required_inputs) {
        $AuditResult.required_inputs = @()
    }

    return $AuditResult
}

function Get-SourceSummary {
    param([string]$Root)

    $allFiles = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue)
    $topDirs = @(Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $extBreakdown = @(
        $allFiles |
            Group-Object { if ([string]::IsNullOrWhiteSpace($_.Extension)) { '[none]' } else { $_.Extension.ToLowerInvariant() } } |
            Sort-Object Count -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                [PSCustomObject]@{
                    extension = $_.Name
                    count = $_.Count
                }
            }
    )

    $readmeCandidates = @('README.md', 'README', 'readme.md', 'Readme.md')
    $hasReadme = $false
    foreach ($candidate in $readmeCandidates) {
        if (Test-Path (Join-Path $Root $candidate) -PathType Leaf) {
            $hasReadme = $true
            break
        }
    }

    $findings = New-Object System.Collections.Generic.List[string]
    if ($allFiles.Count -eq 0) { $findings.Add('Source inventory returned zero files.') }
    if (-not $hasReadme) { $findings.Add('No README marker found at source root.') }

    return @{
        summary = @{
            file_count = $allFiles.Count
            top_level_directories = $topDirs
            extension_breakdown = $extBreakdown
            has_readme = $hasReadme
        }
        findings = @($findings)
    }
}

function Invoke-SourceAuditRepo {
    param([string]$TargetRepoPath)

    if ([string]::IsNullOrWhiteSpace($TargetRepoPath) -or -not (Test-Path $TargetRepoPath -PathType Container)) {
        throw 'TARGET_REPO_PATH is missing or invalid for REPO mode.'
    }

    $repoRoot = (Resolve-Path $TargetRepoPath).Path
    $sourceData = Get-SourceSummary -Root $repoRoot

    return (New-SourceLayer -Overrides @{
            enabled = $true
            kind = 'repo'
            root = $repoRoot
            extracted_root = $null
            base_url = $null
            summary = $sourceData.summary
            findings = $sourceData.findings
            ok = ($sourceData.summary.file_count -gt 0)
        })
}

function Invoke-SourceAuditZip {
    param([string]$InboxPath)

    $zipPath = & (Join-Path $base 'lib/intake_zip.ps1') -InboxPath $InboxPath
    if ([string]::IsNullOrWhiteSpace($zipPath)) {
        throw 'Missing required input: ZIP payload in input/inbox for ZIP mode.'
    }

    & (Join-Path $base 'lib/preflight.ps1') -ZipPath $zipPath | Out-Null

    Reset-Dir -Path $zipWorkRoot

    try {
        Expand-Archive -Path $zipPath -DestinationPath $zipWorkRoot -Force
    }
    catch {
        throw "ZIP extraction failed: $($_.Exception.Message)"
    }

    $inventoryFiles = @(Get-ChildItem -Path $zipWorkRoot -Recurse -File -ErrorAction Stop)
    if ($inventoryFiles.Count -eq 0) {
        throw 'ZIP extraction completed but no files were found in extracted content.'
    }

    $sourceData = Get-SourceSummary -Root $zipWorkRoot

    $zipInfo = Get-Item -Path $zipPath
    return (New-SourceLayer -Overrides @{
            enabled = $true
            kind = 'zip'
            root = $zipInfo.FullName
            extracted_root = $zipWorkRoot
            base_url = $null
            zip_payload = @{
                path = $zipInfo.FullName
                name = $zipInfo.Name
                size_bytes = $zipInfo.Length
                last_write_time = $zipInfo.LastWriteTimeUtc.ToString('o')
            }
            summary = $sourceData.summary
            findings = $sourceData.findings
            ok = ($sourceData.summary.file_count -gt 0)
        })
}

function Invoke-LiveAudit {
    param([string]$BaseUrl)

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return (New-LiveLayer -Overrides @{
            enabled = $false
            required = $false
            root = $null
            base_url = $null
            summary = @{}
            findings = @('BASE_URL was not provided; live audit disabled.')
            warnings = @('Live audit skipped because BASE_URL is missing.')
            ok = $true
        })
    }

    $liveStage = 'CAPTURE'
    $fallbackRouteDetails = @()
    $fallbackRouteCount = 0
    try {
        $captureScript = Join-Path $base 'capture.mjs'
        if (-not (Test-Path $captureScript -PathType Leaf)) {
            throw 'capture.mjs not found.'
        }

        $env:REPORTS_DIR = $reportsDir
        $captureOutput = & node $captureScript 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "capture.mjs execution failed: $($captureOutput -join ' | ')"
        }

        $liveStage = 'LOAD_VISUAL_MANIFEST'
        $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
        if (-not (Test-Path $visualManifestPath -PathType Leaf)) {
            throw 'visual_manifest.json was not generated by capture.mjs.'
        }

        $manifestRaw = Get-Content -Path $visualManifestPath -Raw
        $manifestData = $manifestRaw | ConvertFrom-Json

        $liveStage = 'ROUTE_NORMALIZATION'
        $normalizedRoutesData = Normalize-LiveRoutes -ManifestData $manifestData
        $routes = @($normalizedRoutesData.routes)
        $fallbackRouteDetails = @($routes)
        $fallbackRouteCount = @($routes).Count
        $shapeWarnings = @($normalizedRoutesData.warnings)
        $droppedCount = [int](Safe-Get -Object $normalizedRoutesData -Key 'dropped_count' -Default 0)

        $liveStage = 'ROUTE_MERGE'
        $errored = @($routes | Where-Object {
                $statusValue = Safe-Get -Object $_ -Key 'status' -Default 'error'
                $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
                ($statusValue -eq 'error') -or ($statusCode -ge 400)
            })
        $healthy = @($routes | Where-Object {
                $statusValue = Safe-Get -Object $_ -Key 'status' -Default 'error'
                $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
                ($statusValue -ne 'error') -and ($statusCode -ge 0) -and ($statusCode -lt 400)
            })
        $totalShots = ($routes | Measure-Object -Property screenshotCount -Sum).Sum
        if ($null -eq $totalShots) { $totalShots = 0 }

        $liveStage = 'PAGE_QUALITY_BUILD'
        $routeDetailsAndRollups = Build-PageQualityFindings -Routes $routes
        $routeDetails = @($routeDetailsAndRollups.route_details)
        $rollups = $routeDetailsAndRollups.rollups
        $patternSummary = Safe-Get -Object $routeDetailsAndRollups -Key 'pattern_summary' -Default @{}

        $findings = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $pageQualityStatus = 'EVALUATED'
        if (@($routes).Count -eq 0) {
            $pageQualityStatus = 'NOT_EVALUATED'
            $warnings.Add('PAGE_QUALITY_BUILD: no normalized routes available for evaluation.')
        }
        elseif ($droppedCount -gt 0) {
            $pageQualityStatus = 'PARTIAL'
            $warnings.Add("ROUTE_NORMALIZATION: dropped $droppedCount route entries due to incompatible shape.")
        }
        foreach ($shapeWarning in $shapeWarnings) {
            $warnings.Add($shapeWarning)
        }
        if ($errored.Count -gt 0) { $findings.Add("$($errored.Count) route(s) returned errors or HTTP >= 400.") }
        if ($totalShots -eq 0) { $findings.Add('No screenshots were captured.') }
        if (@($routes).Count -eq 0) { $findings.Add('visual_manifest.json has zero routes.') }
        if ($rollups.empty_routes -gt 0) { $findings.Add("$($rollups.empty_routes) empty route(s) detected.") }
        if ($rollups.thin_routes -gt 0) { $findings.Add("$($rollups.thin_routes) thin route(s) detected.") }
        if ($rollups.weak_cta_routes -gt 0) { $findings.Add("Weak CTA on $($rollups.weak_cta_routes) route(s).") }
        if ($rollups.dead_end_routes -gt 0) { $findings.Add("$($rollups.dead_end_routes) dead-end route(s) detected.") }
        if ($rollups.contaminated_routes -gt 0) { $findings.Add("UI contamination found on $($rollups.contaminated_routes) route(s).") }

        return (New-LiveLayer -Overrides @{
            enabled = $true
            required = $false
            root = $BaseUrl
            base_url = $BaseUrl
            summary = @{
                total_routes = @($routes).Count
                healthy_routes = $healthy.Count
                error_routes = $errored.Count
                screenshot_count = [int]$totalShots
                empty_routes = [int]$rollups.empty_routes
                thin_routes = [int]$rollups.thin_routes
                weak_cta_routes = [int]$rollups.weak_cta_routes
                dead_end_routes = [int]$rollups.dead_end_routes
                contaminated_routes = [int]$rollups.contaminated_routes
                page_quality_status = $pageQualityStatus
                site_pattern_summary = $patternSummary
                raw_route_entries = [int](Safe-Get -Object $normalizedRoutesData -Key 'raw_count' -Default 0)
                normalized_route_entries = @($routes).Count
                dropped_route_entries = $droppedCount
            }
            route_details = $routeDetails
            findings = @($findings)
            warnings = @($warnings)
            ok = (@($routes).Count -gt 0 -and $errored.Count -eq 0 -and [int]$totalShots -gt 0 -and $pageQualityStatus -eq 'EVALUATED')
        })
    }
    catch {
        $failure = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($failure)) { $failure = 'Unknown live audit failure.' }
        return (New-LiveLayer -Overrides @{
            enabled = $true
            required = $false
            root = $BaseUrl
            base_url = $BaseUrl
            summary = @{
                page_quality_status = 'NOT_EVALUATED'
                failure_stage = $liveStage
                evaluation_error = $failure
                total_routes = [int]$fallbackRouteCount
            }
            findings = @("Live audit failed at stage ${liveStage}: $failure")
            warnings = @("Live audit encountered an execution error at stage ${liveStage}: $failure")
            route_details = @($fallbackRouteDetails)
            ok = $false
        })
    }
}


function Get-RoutePrimaryVerdict {
    param(
        [bool]$Empty,
        [bool]$Thin,
        [bool]$WeakCta,
        [bool]$DeadEnd,
        [bool]$UiContamination
    )

    if ($Empty) { return 'EMPTY' }
    if ($UiContamination) { return 'TRUST_CONTAMINATED' }

    $issueCount = 0
    if ($Thin) { $issueCount++ }
    if ($WeakCta) { $issueCount++ }
    if ($DeadEnd) { $issueCount++ }

    if ($issueCount -eq 0) { return 'HEALTHY' }
    if ($WeakCta -and $DeadEnd) { return 'WEAK_DECISION' }
    if ($issueCount -ge 2) { return 'MIXED' }
    if ($WeakCta) { return 'WEAK_CONVERSION' }
    if ($DeadEnd) { return 'DEAD_END' }
    if ($Thin) { return 'THIN' }

    return 'MIXED'
}

function Build-SitePatternSummary {
    param(
        [int]$TotalRoutes,
        [hashtable]$Rollups
    )

    $repeatedPatterns = New-Object System.Collections.Generic.List[object]
    $isolatedPatterns = New-Object System.Collections.Generic.List[object]

    $definitions = @(
        @{ key = 'empty_routes'; label = 'repeated empty-shell pattern'; issue_type = 'coverage/content blocker' },
        @{ key = 'thin_routes'; label = 'repeated thin-content pattern'; issue_type = 'coverage/content blocker' },
        @{ key = 'weak_cta_routes'; label = 'repeated weak-CTA pattern'; issue_type = 'conversion blocker' },
        @{ key = 'dead_end_routes'; label = 'repeated dead-end pattern'; issue_type = 'conversion blocker' },
        @{ key = 'contaminated_routes'; label = 'repeated contamination pattern'; issue_type = 'trust blocker' }
    )

    foreach ($definition in $definitions) {
        $count = [int](Safe-Get -Object $Rollups -Key $definition.key -Default 0)
        if ($count -le 0) { continue }

        $ratio = 0.0
        if ($TotalRoutes -gt 0) {
            $ratio = [math]::Round(($count / [double]$TotalRoutes), 3)
        }

        $pattern = [ordered]@{
            key = $definition.key
            label = $definition.label
            issue_type = $definition.issue_type
            routes_affected = $count
            total_routes = $TotalRoutes
            route_share = $ratio
            scope = if ($count -ge 2) { 'REPEATED' } else { 'ISOLATED' }
        }

        if ($count -ge 2) {
            $repeatedPatterns.Add($pattern)
        }
        else {
            $isolatedPatterns.Add($pattern)
        }
    }

    $dominant = $null
    foreach ($pattern in @($repeatedPatterns + $isolatedPatterns)) {
        if ($null -eq $dominant -or [int]$pattern.routes_affected -gt [int]$dominant.routes_affected) {
            $dominant = $pattern
        }
    }

    return @{
        repeated_patterns = @($repeatedPatterns)
        isolated_patterns = @($isolatedPatterns)
        repeated_pattern_count = [int]$repeatedPatterns.Count
        isolated_pattern_count = [int]$isolatedPatterns.Count
        systemic = ([int]$repeatedPatterns.Count -gt 0)
        dominant_pattern = $dominant
    }
}

function Build-PageQualityFindings {
    param([object[]]$Routes)

    $result = New-Object System.Collections.Generic.List[object]
    $emptyRoutes = 0
    $thinRoutes = 0
    $weakCtaRoutes = 0
    $deadEndRoutes = 0
    $contaminatedRoutes = 0
    $verdictCounts = @{}

    foreach ($route in @($Routes)) {
        $status = Safe-Get -Object $route -Key 'status' -Default 'error'
        $bodyTextLength = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'bodyTextLength' -Default 0) -Default 0
        $links = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'links' -Default 0) -Default 0
        $images = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'images' -Default 0) -Default 0
        $title = [string](Safe-Get -Object $route -Key 'title' -Default '')
        $h1Count = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'h1Count' -Default 0) -Default 0
        $buttonCount = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'buttonCount' -Default 0) -Default 0
        $hasMain = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasMain' -Default $false) -Default $false
        $hasArticle = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasArticle' -Default $false) -Default $false
        $hasNav = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasNav' -Default $false) -Default $false
        $hasFooter = Convert-ToBoolSafe -Value (Safe-Get -Object $route -Key 'hasFooter' -Default $false) -Default $false
        $visibleTextSample = [string](Safe-Get -Object $route -Key 'visibleTextSample' -Default '')
        $contaminationFlags = Convert-ToStringArraySafe -Value (Safe-Get -Object $route -Key 'contaminationFlags' -Default @())
        $normalizedText = ($visibleTextSample + ' ' + $title).ToLowerInvariant()

        $statusCode = 0
        $statusParsed = [int]::TryParse([string]$status, [ref]$statusCode)
        $isErrorRoute = ($status -eq 'error') -or ($statusParsed -and $statusCode -ge 400)
        $empty = $isErrorRoute -or $bodyTextLength -le 120
        $thin = (-not $empty) -and $bodyTextLength -le 420
        $hasActionLanguage = $normalizedText -match '(start|contact|book|schedule|get started|sign up|learn more|request|apply|buy|download|join)'
        $weakCta = (-not $empty) -and $buttonCount -eq 0 -and (-not $hasActionLanguage)
        $deadEnd = (-not $empty) -and (($links + $buttonCount) -le 2) -and (-not $hasNav)
        $uiContamination = @($contaminationFlags).Count -gt 0
        $primaryVerdict = Get-RoutePrimaryVerdict -Empty $empty -Thin $thin -WeakCta $weakCta -DeadEnd $deadEnd -UiContamination $uiContamination

        if ($empty) { $emptyRoutes++ }
        if ($thin) { $thinRoutes++ }
        if ($weakCta) { $weakCtaRoutes++ }
        if ($deadEnd) { $deadEndRoutes++ }
        if ($uiContamination) { $contaminatedRoutes++ }

        if (-not $verdictCounts.ContainsKey($primaryVerdict)) {
            $verdictCounts[$primaryVerdict] = 0
        }
        $verdictCounts[$primaryVerdict] = [int]$verdictCounts[$primaryVerdict] + 1

        $routeFindings = New-Object System.Collections.Generic.List[string]
        if ($empty) { $routeFindings.Add('Route has empty or near-empty visible content.') }
        if ($thin) { $routeFindings.Add('Route content is thin and likely underdeveloped.') }
        if ($weakCta) { $routeFindings.Add('Route lacks clear CTA affordances.') }
        if ($deadEnd) { $routeFindings.Add('Route appears to be a dead-end with limited onward navigation.') }
        if ($uiContamination) { $routeFindings.Add("UI contamination markers detected: $(@($contaminationFlags) -join ', ').") }
        $routeFindings.Add("Primary verdict class: $primaryVerdict")

        $result.Add([ordered]@{
            route_path = Safe-Get -Object $route -Key 'route_path' -Default ''
            status = $status
            screenshotCount = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'screenshotCount' -Default 0) -Default 0
            bodyTextLength = $bodyTextLength
            links = $links
            images = $images
            title = $title
            verdict_class = $primaryVerdict
            page_flags = @{
                empty = $empty
                thin = $thin
                weak_cta = $weakCta
                dead_end = $deadEnd
                ui_contamination = $uiContamination
            }
            findings = @($routeFindings)
            h1Count = $h1Count
            buttonCount = $buttonCount
            hasMain = $hasMain
            hasArticle = $hasArticle
            hasNav = $hasNav
            hasFooter = $hasFooter
            visibleTextSample = $visibleTextSample
            contaminationFlags = @($contaminationFlags)
        })
    }

    $rollups = @{
        empty_routes = [int]$emptyRoutes
        thin_routes = [int]$thinRoutes
        weak_cta_routes = [int]$weakCtaRoutes
        dead_end_routes = [int]$deadEndRoutes
        contaminated_routes = [int]$contaminatedRoutes
        verdict_counts = $verdictCounts
    }

    $patternSummary = Build-SitePatternSummary -TotalRoutes @($Routes).Count -Rollups $rollups

    return @{
        route_details = @($result)
        rollups = $rollups
        pattern_summary = $patternSummary
    }
}

function Build-DecisionLayer {
    param(
        [string]$ResolvedMode,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [string[]]$MissingInputs,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $p0 = New-Object System.Collections.Generic.List[string]
    $p1 = New-Object System.Collections.Generic.List[string]
    $p2 = New-Object System.Collections.Generic.List[string]
    $doNext = New-Object System.Collections.Generic.List[string]

    foreach ($missing in @($MissingInputs)) {
        $p0.Add("Missing required input: $missing")
    }

    if ($ResolvedMode -in @('REPO', 'ZIP') -and $SourceLayer.required) {
        if (-not $SourceLayer.enabled -or -not $SourceLayer.ok) {
            $p0.Add("Source audit failure in $ResolvedMode mode.")
        }
    }

    if ($LiveLayer.required -and (-not $LiveLayer.enabled -or -not $LiveLayer.ok)) {
        $p0.Add("Live audit failure in $ResolvedMode mode.")
    }

    foreach ($warning in $Warnings) {
        $p1.Add($warning)
    }

    if ($SourceLayer.enabled -and $SourceLayer.summary.file_count -gt 0 -and ($SourceLayer.findings | Measure-Object).Count -eq 0) {
        $p2.Add('Source structure baseline looks healthy from inventory scan.')
    }

    if ($LiveLayer.enabled -and $LiveLayer.ok) {
        $p2.Add('Live route capture completed with healthy status codes and screenshots.')
    }

    $liveSummary = @{}
    $patternSummary = @{}
    $pageQualityStatus = 'NOT_EVALUATED'
    $emptyRoutes = 0
    $thinRoutes = 0
    $weakCtaRoutes = 0
    $deadEndRoutes = 0
    $contaminatedRoutes = 0
    $conversionRoutes = 0

    if ($LiveLayer.enabled) {
        $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
        $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
        $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
        $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
        $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
        $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
        $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
        $conversionRoutes = [int]($weakCtaRoutes + $deadEndRoutes)
        $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')

        if ($contaminatedRoutes -ge 2) {
            $p0.Add("Trust blocker: repeated contamination pattern across $contaminatedRoutes route(s).")
        }
        elseif ($contaminatedRoutes -eq 1) {
            $p1.Add('Trust blocker: contamination markers detected on 1 route.')
        }

        if ($emptyRoutes -ge 2) {
            $p0.Add("Coverage/content blocker: $emptyRoutes empty routes require primary-content restoration.")
        }
        elseif ($emptyRoutes -eq 1) {
            $p1.Add('Coverage/content blocker: 1 empty route detected in live pages.')
        }

        if ($thinRoutes -ge 2) {
            $p1.Add("Coverage/content blocker: repeated thin-content pattern on $thinRoutes route(s).")
        }
        elseif ($thinRoutes -eq 1) {
            $p2.Add('Secondary optimization issue: 1 thin route could be strengthened.')
        }

        if ($conversionRoutes -ge 3) {
            $p1.Add("Conversion blocker: weak decision/conversion paths across $conversionRoutes route observations.")
        }
        elseif ($conversionRoutes -gt 0) {
            $p2.Add("Secondary optimization issue: conversion friction present on $conversionRoutes route observation(s).")
        }

        if ($pageQualityStatus -eq 'PARTIAL') {
            $p1.Add('Page-quality evaluation is PARTIAL due to route normalization or merge issues.')
        }
        if ($pageQualityStatus -eq 'NOT_EVALUATED') {
            $p0.Add('Page-quality evaluation is NOT_EVALUATED; live findings are incomplete.')
        }

        if ($emptyRoutes -eq 0 -and $thinRoutes -eq 0 -and $weakCtaRoutes -eq 0 -and $deadEndRoutes -eq 0 -and $contaminatedRoutes -eq 0 -and $LiveLayer.ok -and $pageQualityStatus -eq 'EVALUATED') {
            $p2.Add('No page-quality v1 concerns detected in sampled live routes.')
        }

        $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
        if ($null -ne $dominantPattern) {
            $scope = [string](Safe-Get -Object $dominantPattern -Key 'scope' -Default 'ISOLATED')
            $label = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'route-quality pattern')
            $count = [int](Safe-Get -Object $dominantPattern -Key 'routes_affected' -Default 0)
            $p1.Add("Dominant $scope pattern: $label ($count route(s)).")
        }
    }

    if ($p0.Count -gt 0) {
        $core = $p0[0]
    }
    elseif ($p1.Count -gt 0) {
        $core = $p1[0]
    }
    else {
        if ($ResolvedMode -in @('REPO', 'ZIP')) {
            $core = "Combined source + live audit succeeded for $ResolvedMode mode."
        }
        else {
            $core = 'Live URL audit succeeded for URL mode.'
        }
    }

    if ($p0.Count -gt 0) {
        $doNext.Add('Fix P0 blockers first, then rerun SITE_AUDITOR in the same MODE.')
    }
    if ($LiveLayer.enabled -and $pageQualityStatus -eq 'NOT_EVALUATED') {
        $doNext.Add('Restore page-quality evidence generation first (route capture + normalization), then rerun.')
    }
    if ($emptyRoutes -gt 0 -and $doNext.Count -lt 3) {
        $doNext.Add("Fix empty routes first ($emptyRoutes route(s)) to restore core page coverage.")
    }
    if ($conversionRoutes -gt 0 -and $doNext.Count -lt 3) {
        $doNext.Add("Restore CTA path and onward navigation on weak-conversion routes ($conversionRoutes observations).")
    }
    if ($contaminatedRoutes -gt 0 -and $doNext.Count -lt 3) {
        $doNext.Add("Remove contamination markers on $contaminatedRoutes route(s) to restore trust signals.")
    }
    if ($doNext.Count -lt 3) {
        $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
        if ($null -ne $dominantPattern) {
            $label = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'dominant pattern')
            $doNext.Add("Rerun after fixing the dominant pattern cluster: $label.")
        }
    }
    if ($doNext.Count -lt 3 -and $SourceLayer.enabled) {
        $doNext.Add('Review source summary metrics and extension breakdown for cleanup opportunities.')
    }
    if ($doNext.Count -lt 3 -and $LiveLayer.enabled) {
        $doNext.Add('Review reports/visual_manifest.json and screenshots for route-level detail.')
    }

    return @{
        core_problem = $core
        p0 = @($p0)
        p1 = @($p1)
        p2 = @($p2)
        do_next = @($doNext | Select-Object -First 3)
    }
}

function Build-MetaAuditBriefLines {
    param(
        [hashtable]$AuditResult,
        [hashtable]$Decision,
        [string]$FinalStatus
    )

    $AuditResult = Normalize-AuditResult -AuditResult $AuditResult

    $liveLayer = Safe-Get -Object $AuditResult -Key 'live' -Default @{}
    $liveEnabled = [bool](Safe-Get -Object $liveLayer -Key 'enabled' -Default $false)
    $liveSummary = Safe-Get -Object $liveLayer -Key 'summary' -Default @{}
    $routeDetails = @(Safe-Get -Object $liveLayer -Key 'route_details' -Default @())
    $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
    $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'none')
    $evaluationError = [string](Safe-Get -Object $liveSummary -Key 'evaluation_error' -Default '')

    $runState = 'full'
    if ($FinalStatus -eq 'FAIL') {
        $runState = 'failed'
    }
    elseif ($FinalStatus -eq 'PARTIAL' -or $pageQualityStatus -eq 'PARTIAL') {
        $runState = 'partial'
    }
    elseif ($pageQualityStatus -eq 'NOT_EVALUATED') {
        $runState = 'degraded'
    }

    $confidenceLimiters = New-Object System.Collections.Generic.List[string]
    if (-not $liveEnabled) {
        $confidenceLimiters.Add('live layer disabled: screenshot/route evidence is unavailable.')
    }
    if ($pageQualityStatus -eq 'NOT_EVALUATED') {
        $detail = if (-not [string]::IsNullOrWhiteSpace($evaluationError)) { "$failureStage ($evaluationError)" } else { $failureStage }
        $confidenceLimiters.Add("page-quality status is NOT_EVALUATED at stage: $detail")
    }
    elseif ($pageQualityStatus -eq 'PARTIAL') {
        $confidenceLimiters.Add('page-quality status is PARTIAL; some route evidence may be missing or dropped.')
    }
    if ($FinalStatus -eq 'PARTIAL') {
        $confidenceLimiters.Add('overall run status is PARTIAL.')
    }
    if ($FinalStatus -eq 'FAIL') {
        $confidenceLimiters.Add('overall run status is FAIL.')
    }
    $limiterText = if ($confidenceLimiters.Count -gt 0) { $confidenceLimiters -join ' ' } else { 'none; enabled deterministic checks completed.' }

    $dominantPatternLine = 'mixed pattern / no dominant pattern'
    if ($null -ne $dominantPattern) {
        $label = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'unknown')
        $scope = [string](Safe-Get -Object $dominantPattern -Key 'scope' -Default 'ISOLATED')
        $count = [int](Safe-Get -Object $dominantPattern -Key 'routes_affected' -Default 0)
        $dominantPatternLine = "$label ($scope, $count route(s))"
    }

    $scoredRoutes = New-Object System.Collections.Generic.List[object]
    foreach ($route in @($routeDetails)) {
        $routePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
        if ([string]::IsNullOrWhiteSpace($routePath)) { continue }

        $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
        $empty = [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false)
        $thin = [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)
        $weakCta = [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false)
        $deadEnd = [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)
        $contaminated = [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
        $verdict = [string](Safe-Get -Object $route -Key 'verdict_class' -Default 'UNKNOWN')
        $status = [int](Safe-Get -Object $route -Key 'status' -Default 0)
        $bodyTextLength = [int](Safe-Get -Object $route -Key 'bodyTextLength' -Default 0)

        $score = 0
        if ($empty) { $score += 9 }
        if ($contaminated) { $score += 7 }
        if ($weakCta) { $score += 4 }
        if ($deadEnd) { $score += 4 }
        if ($thin) { $score += 3 }
        if ($status -ge 400 -or $status -eq 0) { $score += 4 }
        if ($verdict -eq 'MIXED') { $score += 2 }
        if ($verdict -eq 'HEALTHY' -and ($bodyTextLength -lt 250 -or $status -ge 400 -or $status -eq 0)) { $score += 2 }

        if ($score -gt 0) {
            $reasons = New-Object System.Collections.Generic.List[string]
            if ($empty) { $reasons.Add('empty') }
            if ($contaminated) { $reasons.Add('trust contamination') }
            if ($thin) { $reasons.Add('thin content') }
            if ($weakCta) { $reasons.Add('weak CTA') }
            if ($deadEnd) { $reasons.Add('dead-end flow') }
            if ($status -ge 400 -or $status -eq 0) { $reasons.Add("status $status") }
            if ($verdict -eq 'HEALTHY' -and ($bodyTextLength -lt 250 -or $status -ge 400 -or $status -eq 0)) { $reasons.Add('healthy verdict but weak evidence signals') }
            $scoredRoutes.Add([ordered]@{
                route_path = $routePath
                score = $score
                verdict = $verdict
                reasons = @($reasons)
            })
        }
    }

    $suspiciousRouteLines = New-Object System.Collections.Generic.List[string]
    if ($scoredRoutes.Count -gt 0) {
        foreach ($item in @($scoredRoutes | Sort-Object -Property @{Expression = 'score'; Descending = $true }, @{Expression = 'route_path'; Descending = $false } | Select-Object -First 6)) {
            $reasonText = if ($item.reasons.Count -gt 0) { $item.reasons -join ', ' } else { 'review required' }
            $suspiciousRouteLines.Add("- $($item.route_path) [verdict=$($item.verdict)] :: $reasonText")
        }
    }
    else {
        $suspiciousRouteLines.Add('- none detected from deterministic route scoring; verify a representative screenshot sample anyway.')
    }

    $formatRouteSet = {
        param([object[]]$Routes, [int]$Max = 3)

        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($routeItem in @($Routes | Select-Object -First $Max)) {
            $path = [string](Safe-Get -Object $routeItem -Key 'route_path' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $paths.Add($path)
            }
        }

        if ($paths.Count -eq 0) { return 'none' }
        return ($paths -join ', ')
    }

    $sortedScoredRoutes = @($scoredRoutes | Sort-Object -Property @{Expression = 'score'; Descending = $true }, @{Expression = 'route_path'; Descending = $false })
    $worstRouteSet = @($sortedScoredRoutes | Select-Object -First 3)
    $suspiciousHealthyRoutes = @($routeDetails | Where-Object {
            $verdict = [string](Safe-Get -Object $_ -Key 'verdict_class' -Default '')
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            $bodyTextLength = [int](Safe-Get -Object $_ -Key 'bodyTextLength' -Default 0)
            $status = [int](Safe-Get -Object $_ -Key 'status' -Default 0)
            $verdict -eq 'HEALTHY' -and (
                [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false) -or
                [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false) -or
                [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -or
                [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false) -or
                [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false) -or
                $bodyTextLength -lt 250 -or
                $status -ge 400 -or $status -eq 0
            )
        })
    $bestHealthyRoutes = @($routeDetails | Where-Object {
            $verdict = [string](Safe-Get -Object $_ -Key 'verdict_class' -Default '')
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            $status = [int](Safe-Get -Object $_ -Key 'status' -Default 0)
            $verdict -eq 'HEALTHY' -and
            -not [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false) -and
            -not [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false) -and
            -not [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -and
            -not [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false) -and
            -not [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false) -and
            $status -gt 0 -and $status -lt 400
        } | Sort-Object -Property @{Expression = { [int](Safe-Get -Object $_ -Key 'bodyTextLength' -Default 0) }; Descending = $true }, @{Expression = { [string](Safe-Get -Object $_ -Key 'route_path' -Default '') }; Descending = $false } | Select-Object -First 3)
    $contaminatedRoutes = @($routeDetails | Where-Object {
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
        })
    $cleanRoutes = @($routeDetails | Where-Object {
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            -not [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
        })

    $dominantKeyword = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default '')
    $dominantRoutes = @()
    if (-not [string]::IsNullOrWhiteSpace($dominantKeyword)) {
        $normalizedDominant = $dominantKeyword.ToLowerInvariant()
        $dominantRoutes = @($routeDetails | Where-Object {
                $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
                ($normalizedDominant -match 'empty' -and [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false)) -or
                ($normalizedDominant -match 'thin' -and [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)) -or
                ($normalizedDominant -match 'weak' -and [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false)) -or
                ($normalizedDominant -match 'dead-end' -and [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)) -or
                ($normalizedDominant -match 'contaminat' -and [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false))
            })
    }

    $screenshotPlan = New-Object System.Collections.Generic.List[string]
    $screenshotPlan.Add("- Start with highest-risk routes: $(& $formatRouteSet $worstRouteSet 3).")
    if (@($dominantRoutes).Count -gt 0) {
        $screenshotPlan.Add("- Validate dominant pattern routes early ($dominantPatternLine): $(& $formatRouteSet $dominantRoutes 3).")
    }
    if ($suspiciousHealthyRoutes.Count -gt 0) {
        $screenshotPlan.Add("- Compare suspicious HEALTHY routes against weak routes to catch false-positive health labels: $(& $formatRouteSet $suspiciousHealthyRoutes 3).")
    }
    if ($runState -in @('partial', 'degraded', 'failed')) {
        $screenshotPlan.Add("- Run is $runState; increase screenshot-first validation because deterministic rollups may be incomplete.")
    }
    if ($screenshotPlan.Count -eq 0) {
        $screenshotPlan.Add('- No deterministic high-risk cluster available; review one route per verdict class from visual_manifest.')
    }

    $comparisonGroups = New-Object System.Collections.Generic.List[string]
    $comparisonGroups.Add("- Worst vs best: [$(& $formatRouteSet $worstRouteSet 2)] vs [$(& $formatRouteSet $bestHealthyRoutes 2)].")
    if ($suspiciousHealthyRoutes.Count -gt 0) {
        $comparisonGroups.Add("- Suspicious HEALTHY vs clearly weak: [$(& $formatRouteSet $suspiciousHealthyRoutes 2)] vs [$(& $formatRouteSet $worstRouteSet 2)].")
    }
    if ($contaminatedRoutes.Count -gt 0) {
        $comparisonGroups.Add("- Trust contamination contrast: contaminated [$(& $formatRouteSet $contaminatedRoutes 2)] vs non-contaminated [$(& $formatRouteSet $cleanRoutes 2)].")
    }
    if ($dominantRoutes.Count -gt 0) {
        $comparisonGroups.Add("- Same dominant verdict-pattern cluster: [$(& $formatRouteSet $dominantRoutes 3)].")
    }

    $repoVsLivePrompts = @(
        '- Do repo/source route structures and templates support what each live route claims to be?',
        '- Where live pages look thin/shell-like, does source/repo show missing content wiring or only presentation weakness?',
        '- Do navigation and CTA elements in source/repo map to what screenshots show, or are critical conversion paths absent live?',
        '- Does each priority route screenshot look like a product-ready page, or only a framework shell despite expected repo structure?'
    )

    $contradictionHotspots = New-Object System.Collections.Generic.List[string]
    if ($suspiciousHealthyRoutes.Count -gt 0) {
        $contradictionHotspots.Add("- HEALTHY-but-suspicious routes need screenshot verification: $(& $formatRouteSet $suspiciousHealthyRoutes 3).")
    }
    if ($contaminatedRoutes.Count -gt 0) {
        $contradictionHotspots.Add("- Summary may look acceptable while contamination is visually obvious on: $(& $formatRouteSet $contaminatedRoutes 3).")
    }
    if ($runState -in @('partial', 'degraded', 'failed')) {
        $contradictionHotspots.Add("- Deterministic wording may understate live severity because run state is $runState; verify screenshot evidence before trusting aggregate text.")
    }
    if ($dominantRoutes.Count -gt 0 -and $worstRouteSet.Count -gt 0) {
        $contradictionHotspots.Add("- Confirm dominant pattern claim by comparing [$(& $formatRouteSet $dominantRoutes 2)] against highest-risk outliers [$(& $formatRouteSet $worstRouteSet 2)].")
    }
    $contradictionHotspots.Add('- Routes classified weak may still show real user value; if screenshots contradict class labels, annotate exact mismatch and route.')

    $focusOrder = @(
        "1) Verify dominant pattern claim against route evidence: $dominantPatternLine.",
        '2) Run screenshot comparisons in the planned order (highest-risk first, then suspicious HEALTHY).',
        '3) Execute repo-vs-live prompts for the same priority routes before making fix recommendations.',
        '4) Resolve contradiction hotspots where deterministic labels and visuals diverge.',
        '5) Decide first-fix order by impact: repeated pattern cluster before isolated route issues.'
    )

    $watchlist = New-Object System.Collections.Generic.List[string]
    if ($pageQualityStatus -eq 'NOT_EVALUATED') {
        $watchlist.Add('- Route-level summary may be weaker than available screenshots because page-quality rollup is NOT_EVALUATED.')
    }
    if ($pageQualityStatus -eq 'PARTIAL') {
        $watchlist.Add('- PARTIAL route evaluation may hide repeated patterns if unsupported entries were dropped.')
    }
    if (@($routeDetails | Where-Object { [string](Safe-Get -Object $_ -Key 'verdict_class' -Default '') -eq 'HEALTHY' -and ([int](Safe-Get -Object $_ -Key 'bodyTextLength' -Default 0) -lt 250) }).Count -gt 0) {
        $watchlist.Add('- Some routes are labeled HEALTHY with low visible text; confirm screenshots are not visually thin.')
    }
    if ([int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0) -gt 0) {
        $watchlist.Add('- Executive wording can flatten repeated pattern severity; cross-check per-route evidence before trusting aggregate summary.')
    }
    $watchlist.Add('- audit_bundle/REPORT.txt is secondary when underlying reports are present; prefer primary truth files first.')

    $decisionQ1 = if ($null -ne $dominantPattern) {
        "Is the dominant problem truly '$([string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'unknown'))', or is another route cluster more severe on screenshots?"
    }
    else {
        'Is the dominant problem content weakness, conversion weakness, trust contamination, or route breakage?'
    }

    return @(
        'AUDIT MISSION',
        'Determine the true dominant site problem from deterministic evidence, then verify visually whether route-level verdicts are credible and prioritized correctly.',
        '',
        'PRIMARY TRUTH FILES',
        '1) reports/audit_result.json',
        '2) reports/run_manifest.json',
        '3) reports/visual_manifest.json',
        '4) reports/11A_EXECUTIVE_SUMMARY.txt',
        'Note: audit_bundle/REPORT.txt is secondary if underlying reports exist.',
        '',
        'RUN STATUS / CONFIDENCE',
        "- Run state: $runState",
        "- Confidence limiters: $limiterText",
        '',
        'DOMINANT SITE PATTERN',
        "- $dominantPatternLine",
        '',
        'SUSPICIOUS ROUTES TO REVIEW'
    ) + @($suspiciousRouteLines) + @(
        '',
        'SCREENSHOT COMPARISON PLAN'
    ) + @($screenshotPlan) + @(
        '',
        'ROUTE COMPARISON GROUPS'
    ) + @($comparisonGroups) + @(
        '',
        'REPO-vs-LIVE CHECK PROMPTS'
    ) + @($repoVsLivePrompts) + @(
        '',
        'REQUIRED ANALYST CHECKS',
        '- Compare screenshots across suspicious routes from reports/visual_manifest.json.',
        '- Compare route verdict_class values in reports/audit_result.json with visible UI in screenshots.',
        '- Compare source/repo claims vs live-page output and ensure both support the same conclusions.',
        '- Check whether a healthy-looking executive summary hides weak visual reality on route-level pages.',
        '- Inspect contamination-related routes and verify trust contamination is visibly present.',
        '- Verify whether summary-level wording contradicts screenshot-level evidence.',
        '',
        'CONTRADICTION HOTSPOTS'
    ) + @($contradictionHotspots) + @(
        '',
        'CONTRADICTION WATCHLIST'
    ) + @($watchlist) + @(
        '',
        'ANALYST FOCUS ORDER'
    ) + @($focusOrder) + @(
        '',
        'WHAT TO DECIDE FIRST',
        "- $decisionQ1",
        '- Do screenshots confirm the deterministic verdict classes on highest-risk routes?',
        '- Does repo/source structure support the live-page claims before prioritizing fixes?',
        '',
        'ANALYST OUTPUT EXPECTATION',
        '- Provide one dominant conclusion.',
        '- Provide one prioritized fix order.',
        '- Provide one confidence note tied to run status and evidence completeness.'
    )
}

function Write-OperatorOutputs {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [hashtable]$AuditResult,
        [hashtable]$Decision
    )

    $AuditResult = Normalize-AuditResult -AuditResult $AuditResult

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    Write-JsonFile -Path $auditResultPath -Data $AuditResult
    $reportFiles.Add('reports/audit_result.json')

    $topIssues = @($Decision.p0 + $Decision.p1)
    if ($topIssues.Count -eq 0) {
        $topIssues = @($Decision.p2)
    }
    if ($topIssues.Count -eq 0) {
        $topIssues = @('No major issues detected from collected source/live evidence.')
    }

    $priorityActions = New-Object System.Collections.Generic.List[string]
    $doNextItems = @($Decision.do_next | Select-Object -First 3)
    if ($doNextItems.Count -gt 0) {
        for ($i = 0; $i -lt $doNextItems.Count; $i++) {
            $priorityActions.Add("$($i + 1)) $($doNextItems[$i])")
        }
    }
    elseif ($FinalStatus -eq 'FAIL') {
        $priorityActions.Add('1) Resolve P0 failures first and rerun the same MODE.')
        $priorityActions.Add('2) Validate required inputs (TARGET_REPO_PATH, ZIP payload, BASE_URL) for the selected MODE.')
        $priorityActions.Add('3) Confirm reports/audit_result.json and REPORT.txt reflect non-empty evidence.')
    }
    else {
        $priorityActions.Add('1) Track P1/P2 findings in the remediation backlog.')
        $priorityActions.Add('2) Re-run SITE_AUDITOR after major content or route changes.')
    }

    $howToFix = @{
        mode = $ResolvedMode
        status = $FinalStatus
        generated_from = 'audit_result.json'
        core_problem = $Decision.core_problem
        top_issues = $topIssues
        priority_actions = $priorityActions
    }
    $howToFixPath = Join-Path $reportsDir 'HOW_TO_FIX.json'
    Write-JsonFile -Path $howToFixPath -Data $howToFix
    $reportFiles.Add('reports/HOW_TO_FIX.json')

    $priorityPath = Join-Path $reportsDir '00_PRIORITY_ACTIONS.txt'
    Write-TextFile -Path $priorityPath -Lines $priorityActions
    $reportFiles.Add('reports/00_PRIORITY_ACTIONS.txt')

    $issuesPath = Join-Path $reportsDir '01_TOP_ISSUES.txt'
    Write-TextFile -Path $issuesPath -Lines $topIssues
    $reportFiles.Add('reports/01_TOP_ISSUES.txt')

    $sourceStatus = if (-not (Safe-Get -Object $AuditResult.source -Key 'enabled' -Default $false)) { 'OFF' } elseif (Safe-Get -Object $AuditResult.source -Key 'ok' -Default $false) { 'PASS' } else { 'FAIL' }
    $liveStatus = if (-not (Safe-Get -Object $AuditResult.live -Key 'enabled' -Default $false)) { 'OFF' } elseif (Safe-Get -Object $AuditResult.live -Key 'ok' -Default $false) { 'PASS' } else { 'FAIL' }
    $requiredInputs = @(Safe-Get -Object $AuditResult -Key 'required_inputs' -Default @())
    $requiredInputsLine = if ($requiredInputs.Count -gt 0) { $requiredInputs -join ', ' } else { 'none' }
    $repoRoot = Safe-Get -Object $AuditResult.source -Key 'root' -Default $null
    $sourceEnabled = [bool](Safe-Get -Object $AuditResult.source -Key 'enabled' -Default $false)

    $summaryLines = @(
        'SITE_AUDITOR EXECUTIVE SUMMARY',
        "Mode: $ResolvedMode",
        "Status: $FinalStatus",
        "Required inputs: $requiredInputsLine",
        "Source audit: $sourceStatus",
        "Live audit: $liveStatus",
        "Core problem: $($Decision.core_problem)",
        "Generated: $timestamp",
        'Primary evidence: reports/audit_result.json'
    )
    $liveSummary = Safe-Get -Object $AuditResult.live -Key 'summary' -Default @{}
    if ([bool](Safe-Get -Object $AuditResult.live -Key 'enabled' -Default $false)) {
        $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
        $summaryLines += "Page quality status: $pageQualityStatus"
        if ($pageQualityStatus -eq 'NOT_EVALUATED') {
            $summaryLines += "- page quality rollup unavailable (stage: $([string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'unknown')))."
        }
        else {
            $summaryLines += 'Page quality rollup:'
            $summaryLines += "- empty routes: $([int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0))"
            $summaryLines += "- thin routes: $([int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0))"
            $summaryLines += "- weak CTA routes: $([int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0))"
            $summaryLines += "- dead-end routes: $([int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0))"
            $summaryLines += "- contaminated routes: $([int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0))"
            $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
            $repeatedCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
            $isolatedCount = [int](Safe-Get -Object $patternSummary -Key 'isolated_pattern_count' -Default 0)
            $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
            $summaryLines += "- repeated site patterns: $repeatedCount"
            $summaryLines += "- isolated issue patterns: $isolatedCount"
            if ($null -ne $dominantPattern) {
                $summaryLines += "- dominant pattern: $([string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'unknown'))"
            }
        }
    }
    $summaryPath = Join-Path $reportsDir '11A_EXECUTIVE_SUMMARY.txt'
    Write-TextFile -Path $summaryPath -Lines $summaryLines
    $reportFiles.Add('reports/11A_EXECUTIVE_SUMMARY.txt')

    $metaBriefPath = Join-Path $reportsDir '12A_META_AUDIT_BRIEF.txt'
    $metaBriefLines = Build-MetaAuditBriefLines -AuditResult $AuditResult -Decision $Decision -FinalStatus $FinalStatus
    Write-TextFile -Path $metaBriefPath -Lines $metaBriefLines
    $reportFiles.Add('reports/12A_META_AUDIT_BRIEF.txt')

    $reportLines = @(
        "MODE: $ResolvedMode",
        "REQUIRED INPUTS: $requiredInputsLine",
        "SOURCE AUDIT: $sourceStatus",
        "LIVE AUDIT: $liveStatus",
        "OVERALL STATUS: $FinalStatus",
        "CORE PROBLEM: $($Decision.core_problem)",
        'P0:'
    )
    if ([bool](Safe-Get -Object $AuditResult.live -Key 'enabled' -Default $false)) {
        $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
        $reportLines += "PAGE QUALITY STATUS: $pageQualityStatus"
        if ($pageQualityStatus -eq 'NOT_EVALUATED') {
            $reportLines += "PAGE QUALITY ROLLUP: unavailable (stage: $([string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'unknown')))"
        }
        else {
            $reportLines += 'PAGE QUALITY ROLLUP:'
            $reportLines += "- empty routes: $([int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0))"
            $reportLines += "- thin routes: $([int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0))"
            $reportLines += "- weak CTA routes: $([int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0))"
            $reportLines += "- dead-end routes: $([int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0))"
            $reportLines += "- contaminated routes: $([int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0))"
            $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
            $repeatedCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
            $isolatedCount = [int](Safe-Get -Object $patternSummary -Key 'isolated_pattern_count' -Default 0)
            $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
            $reportLines += "REPEATED SITE PATTERNS: $repeatedCount"
            $reportLines += "ISOLATED ISSUE PATTERNS: $isolatedCount"
            if ($null -ne $dominantPattern) {
                $reportLines += "DOMINANT PATTERN: $([string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'unknown'))"
            }
        }
    }
    $reportLines += if ($Decision.p0.Count -gt 0) { $Decision.p0 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'P1:'
    $reportLines += if ($Decision.p1.Count -gt 0) { $Decision.p1 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'P2:'
    $reportLines += if ($Decision.p2.Count -gt 0) { $Decision.p2 | ForEach-Object { "- $_" } } else { '- none' }
    $reportLines += 'DO NEXT:'
    $reportLines += if ($Decision.do_next.Count -gt 0) { $Decision.do_next | ForEach-Object { "- $_" } } else { '- none' }

    $manifest = @{
        mode = $ResolvedMode
        status = $FinalStatus
        repo_root = $repoRoot
        target_repo_bound = $sourceEnabled
        output_root = $base
        report_files = @($reportFiles)
        timestamp = $timestamp
    }

    $manifestPath = Join-Path $reportsDir 'run_manifest.json'
    Write-JsonFile -Path $manifestPath -Data $manifest
    $reportFiles.Add('reports/run_manifest.json')
    $reportLines += 'MANIFEST: reports/run_manifest.json'

    $reportPath = Join-Path $outboxDir 'REPORT.txt'
    Write-TextFile -Path $reportPath -Lines $reportLines
}

function Ensure-OutputContract {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [string]$FailureReason
    )

    Ensure-Dir $outboxDir
    Ensure-Dir $reportsDir

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    if (-not (Test-Path $auditResultPath -PathType Leaf)) {
        $fallbackAuditResult = @{
            status = $FinalStatus
            timestamp = (Get-Date).ToString('o')
            mode = $ResolvedMode
            error = if ([string]::IsNullOrWhiteSpace($FailureReason)) { 'FAILED: no report generated' } else { $FailureReason }
        }
        Write-JsonFile -Path $auditResultPath -Data $fallbackAuditResult
    }

    $reportPath = Join-Path $outboxDir 'REPORT.txt'
    if (-not (Test-Path $reportPath -PathType Leaf)) {
        $fallbackReason = if ([string]::IsNullOrWhiteSpace($FailureReason)) { 'no report generated' } else { $FailureReason }
        $fallbackLines = @(
            "MODE: $ResolvedMode",
            "OVERALL STATUS: $FinalStatus",
            "FAILED: $fallbackReason",
            'Primary evidence: reports/audit_result.json'
        )
        Write-TextFile -Path $reportPath -Lines $fallbackLines
    }

    $doneOk = Join-Path $outboxDir 'DONE.ok'
    $doneFail = Join-Path $outboxDir 'DONE.fail'
    if (Test-Path $doneOk) { Remove-Item $doneOk -Force }
    if (Test-Path $doneFail) { Remove-Item $doneFail -Force }

    if ($FinalStatus -eq 'PASS' -and $null -eq $global:AuditError) {
        New-Item -ItemType File -Path $doneOk -Force | Out-Null
    }
    else {
        New-Item -ItemType File -Path $doneFail -Force | Out-Null
    }
}

$resolvedMode = $MODE.ToUpperInvariant()
$warnings = New-Object System.Collections.Generic.List[string]
$requiredInputs = @()
$missingInputs = New-Object System.Collections.Generic.List[string]
$sourceLayer = New-SourceLayer
$liveLayer = New-LiveLayer

try {
    Ensure-Dir $outboxDir
    Ensure-Dir $reportsDir
    Ensure-Dir $runtimeDir

    switch ($resolvedMode) {
        'REPO' {
            $requiredInputs = @('TARGET_REPO_PATH', 'BASE_URL')
            $sourceLayer.required = $true
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:TARGET_REPO_PATH)) { $missingInputs.Add('TARGET_REPO_PATH') }
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for REPO mode: " + ($missingInputs -join ', ')) }
            $sourceLayer = New-SourceLayer -Overrides (Invoke-SourceAuditRepo -TargetRepoPath $env:TARGET_REPO_PATH)
            $sourceLayer.required = $true
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        'ZIP' {
            $requiredInputs = @('ZIP payload in input/inbox', 'BASE_URL')
            $sourceLayer.required = $true
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for ZIP mode: " + ($missingInputs -join ', ')) }
            $sourceLayer = New-SourceLayer -Overrides (Invoke-SourceAuditZip -InboxPath (Join-Path $base 'input/inbox'))
            $sourceLayer.required = $true
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        'URL' {
            $requiredInputs = @('BASE_URL')
            $liveLayer.required = $true
            if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) { $missingInputs.Add('BASE_URL') }
            if ($missingInputs.Count -gt 0) { throw ("Missing required input(s) for URL mode: " + ($missingInputs -join ', ')) }
            $liveLayer = Invoke-LiveAudit -BaseUrl $env:BASE_URL
            $liveLayer.required = $true
        }
        default {
            throw "Unsupported mode: $MODE"
        }
    }

    $sourceLayer = New-SourceLayer -Overrides $sourceLayer
    $liveLayer = New-LiveLayer -Overrides $liveLayer

    foreach ($lw in @($liveLayer.warnings)) { $warnings.Add($lw) }

    $decision = Build-DecisionLayer -ResolvedMode $resolvedMode -SourceLayer $sourceLayer -LiveLayer $liveLayer -MissingInputs @($missingInputs) -Warnings $warnings

    $status = 'PASS'
    if ($missingInputs.Count -gt 0) { $status = 'FAIL' }
    if ($sourceLayer.required -and (-not $sourceLayer.enabled -or -not $sourceLayer.ok)) { $status = 'FAIL' }
    if ($liveLayer.required -and (-not $liveLayer.enabled -or -not $liveLayer.ok)) { $status = 'FAIL' }

    $auditResult = @{
        status = $status
        timestamp = $timestamp
        mode = $resolvedMode
        required_inputs = $requiredInputs
        source = @{
            enabled = [bool]$sourceLayer.enabled
            required = [bool]$sourceLayer.required
            ok = [bool]$sourceLayer.ok
            kind = $sourceLayer.kind
            root = $sourceLayer.root
            extracted_root = $sourceLayer.extracted_root
            base_url = $sourceLayer.base_url
            summary = $sourceLayer.summary
            findings = @($sourceLayer.findings)
        }
        live = @{
            enabled = [bool]$liveLayer.enabled
            required = [bool]$liveLayer.required
            ok = [bool]$liveLayer.ok
            root = $liveLayer.root
            base_url = $liveLayer.base_url
            summary = $liveLayer.summary
            route_details = @(Safe-Get -Object $liveLayer -Key 'route_details' -Default @())
            findings = @($liveLayer.findings)
        }
        decision = $decision
    }

    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus $status -AuditResult $auditResult -Decision $decision
}
catch {
    $global:AuditError = $_
    $status = 'FAIL'

    $failureReason = $global:AuditError.Exception.Message
    if (-not $failureReason) { $failureReason = 'Unknown failure while running SITE_AUDITOR.' }

    $sourceLayer = New-SourceLayer -Overrides $sourceLayer
    $liveLayer = New-LiveLayer -Overrides $liveLayer

    $decision = @{
        core_problem = $failureReason
        p0 = @($failureReason)
        p1 = @($warnings)
        p2 = @()
        do_next = @('Resolve the failure reason and rerun SITE_AUDITOR.')
    }

    $auditResult = @{
        status = 'FAIL'
        timestamp = $timestamp
        mode = $resolvedMode
        required_inputs = $requiredInputs
        source = @{
            enabled = [bool]$sourceLayer.enabled
            required = [bool]$sourceLayer.required
            ok = [bool]$sourceLayer.ok
            kind = $sourceLayer.kind
            root = $sourceLayer.root
            extracted_root = $sourceLayer.extracted_root
            base_url = $sourceLayer.base_url
            summary = $sourceLayer.summary
            findings = @($sourceLayer.findings)
        }
        live = @{
            enabled = [bool]$liveLayer.enabled
            required = [bool]$liveLayer.required
            ok = [bool]$liveLayer.ok
            root = $liveLayer.root
            base_url = $liveLayer.base_url
            summary = $liveLayer.summary
            route_details = @(Safe-Get -Object $liveLayer -Key 'route_details' -Default @())
            findings = @($liveLayer.findings)
        }
        decision = $decision
    }

    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus 'FAIL' -AuditResult $auditResult -Decision $decision
}
finally {
    Ensure-OutputContract -ResolvedMode $resolvedMode -FinalStatus $status -FailureReason $failureReason
}

if ($status -eq 'PASS' -and $null -eq $global:AuditError) {
    Write-Host "SITE_AUDITOR completed successfully. Artifacts: $outboxDir ; $reportsDir"
    exit 0
}

Write-Host "SITE_AUDITOR failed. Artifacts: $outboxDir ; $reportsDir"
exit 1
