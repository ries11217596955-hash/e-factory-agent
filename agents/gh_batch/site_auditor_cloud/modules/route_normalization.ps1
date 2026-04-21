Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ManifestRoutes {
    param([object]$ManifestData)

    if ($null -eq $ManifestData) { return @() }

    if ($ManifestData -is [System.Collections.IDictionary] -or $ManifestData -is [PSCustomObject]) {
        $explicitRoutes = Safe-Get -Object $ManifestData -Key 'routes' -Default $null
        if ($null -ne $explicitRoutes) {
            $explicitRoutes = Convert-ToStringKeyDictionarySafe -Value $explicitRoutes
            if ($explicitRoutes -is [System.Collections.IDictionary]) {
                $mappedRoutes = New-Object System.Collections.Generic.List[object]
                foreach ($entry in @($explicitRoutes.GetEnumerator())) {
                    $entryKey = Safe-Get -Object $entry -Key 'Key' -Default ''
                    $entryValue = Safe-Get -Object $entry -Key 'Value' -Default $null
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

function Get-RouteCoverageCategory {
    param([string]$RoutePath)

    if ([string]::IsNullOrWhiteSpace($RoutePath)) { return 'OTHER' }
    $normalized = $RoutePath.Trim().ToLowerInvariant()
    if ($normalized -eq '/') { return 'ROOT' }
    if ($normalized.StartsWith('/hubs')) { return 'HUB' }
    if ($normalized.StartsWith('/tools')) { return 'TOOL' }
    if ($normalized.StartsWith('/search')) { return 'SEARCH' }
    if ($normalized.StartsWith('/start-here')) { return 'START' }
    return 'CONTENT'
}

function Build-EvidenceCoverageSummary {
    param([object[]]$Routes)

    $routes = @($Routes)
    $categoryCounts = [ordered]@{
        ROOT = 0
        HUB = 0
        TOOL = 0
        SEARCH = 0
        START = 0
        CONTENT = 0
        OTHER = 0
    }
    $screenshotCoverage = [ordered]@{
        full = 0
        partial = 0
        none = 0
    }
    $captureProfiles = @{}
    $expectedScreenshots = 3
    $totalShots = 0

    foreach ($route in $routes) {
        $routePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
        $category = [string](Safe-Get -Object $route -Key 'route_category' -Default '')
        if ([string]::IsNullOrWhiteSpace($category)) {
            $category = Get-RouteCoverageCategory -RoutePath $routePath
        }
        if (-not $categoryCounts.Contains($category)) {
            $categoryCounts[$category] = 0
        }
        $categoryCounts[$category] = [int]$categoryCounts[$category] + 1

        $shots = Convert-ToIntSafe -Value (Safe-Get -Object $route -Key 'screenshotCount' -Default 0) -Default 0
        $totalShots += $shots
        if ($shots -ge $expectedScreenshots) {
            $screenshotCoverage.full++
        }
        elseif ($shots -gt 0) {
            $screenshotCoverage.partial++
        }
        else {
            $screenshotCoverage.none++
        }

        $profile = [string](Safe-Get -Object $route -Key 'capture_profile' -Default 'UNKNOWN')
        if ([string]::IsNullOrWhiteSpace($profile)) { $profile = 'UNKNOWN' }
        if (-not $captureProfiles.ContainsKey($profile)) {
            $captureProfiles[$profile] = 0
        }
        $captureProfiles[$profile] = [int]$captureProfiles[$profile] + 1
    }

    $distinctCategories = @($categoryCounts.Keys | Where-Object { [int]$categoryCounts[$_] -gt 0 })
    $richness = 'SPARSE'
    if ($routes.Count -ge 5 -and $distinctCategories.Count -ge 4 -and [int]$screenshotCoverage.full -ge [math]::Ceiling($routes.Count * 0.60)) {
        $richness = 'RICH'
    }
    elseif ($routes.Count -ge 3 -and $distinctCategories.Count -ge 2 -and [int]$screenshotCoverage.partial -le 1 -and [int]$screenshotCoverage.none -eq 0) {
        $richness = 'MODERATE'
    }

    return @{
        route_coverage = @{
            category_counts = $categoryCounts
            distinct_category_count = [int]$distinctCategories.Count
            sampled_routes = [int]$routes.Count
        }
        screenshot_coverage = @{
            expected_per_route = $expectedScreenshots
            total_captured = [int]$totalShots
            full_routes = [int]$screenshotCoverage.full
            partial_routes = [int]$screenshotCoverage.partial
            no_screenshot_routes = [int]$screenshotCoverage.none
        }
        capture_profiles = $captureProfiles
        evidence_richness = $richness
    }
}

function Normalize-LiveRoutes {
    param([object]$ManifestData)

    $global:RouteNormalizationForensics = $null
    $global:RouteNormalizationTrace = @()
    $global:RouteNormalizationAggregateTrace = @()
    $rawRoutes = @(Resolve-ManifestRoutes -ManifestData $ManifestData)

    $normalized = New-Object System.Collections.Generic.List[object]
    $shapeWarnings = New-Object System.Collections.Generic.List[string]
    $routePathByIndex = @{}

    for ($index = 0; $index -lt @($rawRoutes).Count; $index++) {
        $route = $rawRoutes[$index]
        Add-RouteNormalizationTracePhase -PhaseName 'raw_route_entry' -RouteIndex $index -PhaseObject $route -Status 'ok'

        if ($null -eq $route) {
            Add-RouteNormalizationTracePhase -PhaseName 'route_after_string_key_normalization' -RouteIndex $index -PhaseObject $null -Status 'skipped'
            Add-RouteNormalizationTracePhase -PhaseName 'route_path_extraction' -RouteIndex $index -PhaseObject $null -Status 'skipped'
            Add-RouteNormalizationTracePhase -PhaseName 'route_signal_fields' -RouteIndex $index -PhaseObject $null -Status 'skipped'
            Add-RouteNormalizationTracePhase -PhaseName 'normalized_route_output' -RouteIndex $index -PhaseObject $null -Status 'skipped'
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped null route entry at index $index.")
            continue
        }

        try {
            $route = Convert-ToStringKeyDictionarySafe -Value $route
            Add-RouteNormalizationTracePhase -PhaseName 'route_after_string_key_normalization' -RouteIndex $index -PhaseObject $route -Status 'ok'
        }
        catch {
            Add-RouteNormalizationTracePhase -PhaseName 'route_after_string_key_normalization' -RouteIndex $index -PhaseObject $route -Status 'failed' -OperationLabel 'OP_ROUTE_STRING_KEY_NORMALIZE' -Expression 'Convert-ToStringKeyDictionarySafe -Value $route' -ErrorRecord $_ -LeftOperand $route -RightOperand $null
            throw
        }

        if (-not ($route -is [System.Collections.IDictionary] -or $route -is [PSCustomObject])) {
            Add-RouteNormalizationTracePhase -PhaseName 'route_path_extraction' -RouteIndex $index -PhaseObject $route -Status 'skipped'
            Add-RouteNormalizationTracePhase -PhaseName 'route_signal_fields' -RouteIndex $index -PhaseObject $route -Status 'skipped'
            Add-RouteNormalizationTracePhase -PhaseName 'normalized_route_output' -RouteIndex $index -PhaseObject $route -Status 'skipped'
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped non-object route entry at index $index of type $($route.GetType().FullName).")
            continue
        }

        $routePath = ''
        $activePhase = 'route_path_extraction'
        $activeOperationLabel = 'OP_ROUTE_PATH_EXTRACT'
        $activeExpression = '$routePathRaw/$routePath extraction from route_path/routePath/url'
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
            $routePathByIndex[[string]$index] = $routePath
            Add-RouteNormalizationTracePhase -PhaseName 'route_path_extraction' -RouteIndex $index -RoutePathIfAvailable $routePath -PhaseObject ([ordered]@{
                    route_path_raw = $routePathRaw
                    route_path = $routePath
                }) -Status 'ok'

            $activePhase = 'route_signal_fields'
            $activeOperationLabel = 'OP_ROUTE_SIGNAL_FIELDS'
            $activeExpression = 'status/category/capture_profile/flags extraction'
            $statusValue = Safe-Get -Object $route -Key 'status' -Default 'error'
            $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
            $normalizedStatus = if ($statusCode -ge 0) { $statusCode } else { [string]$statusValue }

            $flags = Convert-ToStringArraySafe -Value (Safe-Get -Object $route -Key 'contaminationFlags' -Default @())
            $routeCategory = [string](Safe-Get -Object $route -Key 'routeCategory' -Default (Safe-Get -Object $route -Key 'route_category' -Default ''))
            if ([string]::IsNullOrWhiteSpace($routeCategory)) {
                $routeCategory = Get-RouteCoverageCategory -RoutePath $routePath
            }
            $captureProfile = [string](Safe-Get -Object $route -Key 'captureProfile' -Default (Safe-Get -Object $route -Key 'capture_profile' -Default 'TRIPLE_SCROLL'))
            if ([string]::IsNullOrWhiteSpace($captureProfile)) { $captureProfile = 'TRIPLE_SCROLL' }
            Add-RouteNormalizationTracePhase -PhaseName 'route_signal_fields' -RouteIndex $index -RoutePathIfAvailable $routePath -PhaseObject ([ordered]@{
                    status_value = $statusValue
                    status_code = $statusCode
                    normalized_status = $normalizedStatus
                    route_category = $routeCategory
                    capture_profile = $captureProfile
                    contamination_flags = @($flags)
                }) -Status 'ok'

            $activePhase = 'normalized_route_output'
            $activeOperationLabel = 'OP_ROUTE_ENTRY_NORMALIZE'
            $activeExpression = 'normalized route object assembly'
            $normalizedRoute = [ordered]@{
                    route_path = $routePath
                    route_category = $routeCategory
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
                    capture_profile = $captureProfile
                }
            $normalized.Add($normalizedRoute)
            Add-RouteNormalizationTracePhase -PhaseName 'normalized_route_output' -RouteIndex $index -RoutePathIfAvailable $routePath -PhaseObject $normalizedRoute -Status 'ok'
        }
        catch {
            $routeError = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($routeError)) { $routeError = 'Unknown route normalization error.' }
            Add-RouteNormalizationTracePhase -PhaseName $activePhase -RouteIndex $index -RoutePathIfAvailable $routePath -PhaseObject $route -Status 'failed' -OperationLabel $activeOperationLabel -Expression $activeExpression -ErrorRecord $_ -LeftOperand $route -RightOperand $null
            Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -OperationLabel $activeOperationLabel -Expression $activeExpression -LeftOperand $route -RightOperand $null -VariableNames @('route') -AdditionalContext @{
                activePhase = $activePhase
                route_index = $index
                phase_name = $activePhase
                route_error = $routeError
                stack_hint = $_.ScriptStackTrace
            }
            $shapeWarnings.Add("ROUTE_NORMALIZATION: dropped route index $index due to normalization error: $routeError")
            continue
        }
    }

    $aggregateComputedCounts = [ordered]@{
        raw_route_count = $null
        normalized_count = $null
        dropped_delta = $null
        dropped_count = $null
    }

    $rawRouteCount = $null
    try {
        $rawRouteCountRead = @($rawRoutes).Count
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_raw_route_count_read' -OperationLabel 'OP1A_raw_route_count_read' -Expression '@($rawRoutes).Count' -LeftOperand $rawRoutes -RightOperand $rawRouteCountRead -Status 'ok'
        $rawRouteCount = Convert-ToIntSafe -Value $rawRouteCountRead -Default 0
        $aggregateComputedCounts.raw_route_count = $rawRouteCount
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_raw_route_count_coerce' -OperationLabel 'OP1B_raw_route_count_to_int' -Expression 'Convert-ToIntSafe -Value $rawRouteCountRead -Default 0' -LeftOperand $rawRouteCountRead -RightOperand $rawRouteCount -Status 'ok'
    }
    catch {
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_raw_route_count' -OperationLabel 'OP1_raw_route_count' -Expression '@($rawRoutes).Count -> Convert-ToIntSafe' -LeftOperand $rawRoutes -RightOperand $rawRouteCount -Status 'failed' -ErrorRecord $_
        Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_raw_route_count' -ActiveOperationLabel 'OP1_raw_route_count' -ActiveExpression '@($rawRoutes).Count -> Convert-ToIntSafe' -OperationLabel 'OP1_raw_route_count' -Expression '@($rawRoutes).Count -> Convert-ToIntSafe' -LeftOperand $rawRoutes -RightOperand $rawRouteCount -VariableNames @('rawRoutes', 'rawRouteCountRead', 'rawRouteCount') -AdditionalContext @{
            counts_computed_before_failure = $aggregateComputedCounts
            stack_hint = $_.ScriptStackTrace
        }
        throw
    }

    $normalizedCount = $null
    $normalizedCountRead = $null
    $normalizedCountReadScalar = $null
    $normalizedCountSource = $null
    $normalizedShape = $null
    $normalizedCountSourceShape = $null
    $normalizedCountReadShape = $null
    try {
        try {
            $normalizedShape = Get-ObjectShapeSummary -Value $normalized
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_shape_capture' -OperationLabel 'OP2A_normalized_shape_capture' -Expression 'Get-ObjectShapeSummary -Value $normalized' -LeftOperand $normalized -RightOperand $normalizedShape -Status 'ok'
        }
        catch {
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_shape_capture' -OperationLabel 'OP2A_normalized_shape_capture' -Expression 'Get-ObjectShapeSummary -Value $normalized' -LeftOperand $normalized -RightOperand $normalizedShape -Status 'failed' -ErrorRecord $_
            Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_normalized_shape_capture' -ActiveOperationLabel 'OP2A_normalized_shape_capture' -ActiveExpression 'Get-ObjectShapeSummary -Value $normalized' -OperationLabel 'OP2A_normalized_shape_capture' -Expression 'Get-ObjectShapeSummary -Value $normalized' -LeftOperand $normalized -RightOperand $normalizedShape -VariableNames @('normalized', 'normalizedShape') -AdditionalContext @{
                counts_computed_before_failure = $aggregateComputedCounts
                stack_hint = $_.ScriptStackTrace
            }
            throw
        }

        try {
            if ($normalized -is [System.Collections.ICollection]) {
                $normalizedCountSource = $normalized
            }
            elseif ($normalized -is [System.Collections.IEnumerable] -and -not ($normalized -is [string])) {
                $normalizedCountSource = Convert-ToObjectArraySafe -Value $normalized
            }
            else {
                $normalizedCountSource = @()
            }
            $normalizedCountSourceShape = Get-ObjectShapeSummary -Value $normalizedCountSource
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_source' -OperationLabel 'OP2B_normalized_count_source' -Expression '$normalized (count source selection)' -LeftOperand $normalized -RightOperand $normalizedCountSource -Status 'ok'
        }
        catch {
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_source' -OperationLabel 'OP2B_normalized_count_source' -Expression '$normalized (count source selection)' -LeftOperand $normalized -RightOperand $normalizedCountSource -Status 'failed' -ErrorRecord $_
            Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_normalized_count_source' -ActiveOperationLabel 'OP2B_normalized_count_source' -ActiveExpression '$normalized (count source selection)' -OperationLabel 'OP2B_normalized_count_source' -Expression '$normalized (count source selection)' -LeftOperand $normalized -RightOperand $normalizedCountSource -VariableNames @('normalized', 'normalizedShape', 'normalizedCountSource', 'normalizedCountSourceShape') -AdditionalContext @{
                counts_computed_before_failure = $aggregateComputedCounts
                normalized_shape = $normalizedShape
                normalized_count_source_shape = $normalizedCountSourceShape
                stack_hint = $_.ScriptStackTrace
            }
            throw
        }

        try {
            if ($normalizedCountSource -is [System.Collections.ICollection]) {
                $normalizedCountRead = $normalizedCountSource.Count
            }
            elseif ($normalizedCountSource -is [System.Collections.IEnumerable] -and -not ($normalizedCountSource -is [string])) {
                $normalizedCountRead = (Convert-ToObjectArraySafe -Value $normalizedCountSource).Count
            }
            else {
                $normalizedCountRead = 0
            }
            if ($normalizedCountRead -is [string]) {
                $normalizedCountReadScalar = [string]$normalizedCountRead
            }
            elseif ($normalizedCountRead -is [System.Collections.IEnumerable]) {
                $normalizedCountReadScalar = @($normalizedCountRead | Select-Object -First 1)
                if (@($normalizedCountReadScalar).Count -gt 0) {
                    $normalizedCountReadScalar = $normalizedCountReadScalar[0]
                }
                else {
                    $normalizedCountReadScalar = 0
                }
            }
            else {
                $normalizedCountReadScalar = $normalizedCountRead
            }
            try {
                $normalizedCountReadShape = Get-ObjectShapeSummary -Value $normalizedCountReadScalar
            }
            catch {
                $normalizedCountReadShape = [ordered]@{
                    type = '<shape_capture_failed>'
                    keys = @()
                    property_names = @()
                    count = 0
                    error_message = if ($null -eq $_ -or $null -eq $_.Exception) { '' } else { [string]$_.Exception.Message }
                }
            }
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_read' -OperationLabel 'OP2C_normalized_count_read' -Expression '$normalizedCountSource -> safe count read -> scalarized' -LeftOperand $normalizedCountSource -RightOperand $normalizedCountReadScalar -Status 'ok'
        }
        catch {
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_read' -OperationLabel 'OP2C_normalized_count_read' -Expression '$normalizedCountSource -> safe count read -> scalarized' -LeftOperand $normalizedCountSource -RightOperand $normalizedCountReadScalar -Status 'failed' -ErrorRecord $_
            Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_normalized_count_read' -ActiveOperationLabel 'OP2C_normalized_count_read' -ActiveExpression '$normalizedCountSource -> safe count read -> scalarized' -OperationLabel 'OP2C_normalized_count_read' -Expression '$normalizedCountSource -> safe count read -> scalarized' -LeftOperand $normalizedCountSource -RightOperand $normalizedCountReadScalar -VariableNames @('normalized', 'normalizedShape', 'normalizedCountSource', 'normalizedCountSourceShape', 'normalizedCountRead', 'normalizedCountReadScalar', 'normalizedCountReadShape') -AdditionalContext @{
                counts_computed_before_failure = $aggregateComputedCounts
                normalized_shape = $normalizedShape
                normalized_count_source_shape = $normalizedCountSourceShape
                normalized_count_read_raw_sample = Get-DebugValueSample -Value $normalizedCountRead
                normalized_count_read_shape = $normalizedCountReadShape
                stack_hint = $_.ScriptStackTrace
            }
            throw
        }

        try {
            $normalizedCount = Convert-ToIntSafe -Value $normalizedCountReadScalar -Default 0
            $aggregateComputedCounts.normalized_count = $normalizedCount
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_coerce' -OperationLabel 'OP2D_normalized_count_to_int' -Expression 'Convert-ToIntSafe -Value $normalizedCountReadScalar -Default 0' -LeftOperand $normalizedCountReadScalar -RightOperand $normalizedCount -Status 'ok'
        }
        catch {
            Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_normalized_count_coerce' -OperationLabel 'OP2D_normalized_count_to_int' -Expression 'Convert-ToIntSafe -Value $normalizedCountReadScalar -Default 0' -LeftOperand $normalizedCountReadScalar -RightOperand $normalizedCount -Status 'failed' -ErrorRecord $_
            Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_normalized_count_coerce' -ActiveOperationLabel 'OP2D_normalized_count_to_int' -ActiveExpression 'Convert-ToIntSafe -Value $normalizedCountReadScalar -Default 0' -OperationLabel 'OP2D_normalized_count_to_int' -Expression 'Convert-ToIntSafe -Value $normalizedCountReadScalar -Default 0' -LeftOperand $normalizedCountReadScalar -RightOperand $normalizedCount -VariableNames @('normalized', 'normalizedShape', 'normalizedCountSource', 'normalizedCountSourceShape', 'normalizedCountRead', 'normalizedCountReadScalar', 'normalizedCountReadShape', 'normalizedCount') -AdditionalContext @{
                counts_computed_before_failure = $aggregateComputedCounts
                normalized_shape = $normalizedShape
                normalized_count_source_shape = $normalizedCountSourceShape
                normalized_count_read_raw_sample = Get-DebugValueSample -Value $normalizedCountRead
                normalized_count_read_shape = $normalizedCountReadShape
                stack_hint = $_.ScriptStackTrace
            }
            throw
        }
    }
    catch {
        throw
    }

    $droppedDelta = $null
    try {
        $rawRouteCountInt = Convert-ToIntSafe -Value $rawRouteCount -Default 0
        $normalizedCountInt = Convert-ToIntSafe -Value $normalizedCount -Default 0
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_count_subtraction_input_coerce' -OperationLabel 'OP3A_subtraction_input_to_int' -Expression 'Convert-ToIntSafe(rawRouteCount/normalizedCount)' -LeftOperand $rawRouteCountInt -RightOperand $normalizedCountInt -Status 'ok'
        $droppedDelta = [int]($rawRouteCountInt - $normalizedCountInt)
        $aggregateComputedCounts.dropped_delta = $droppedDelta
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_count_subtraction' -OperationLabel 'OP3B_count_subtraction' -Expression '[int]($rawRouteCountInt - $normalizedCountInt)' -LeftOperand $rawRouteCountInt -RightOperand $normalizedCountInt -Status 'ok'
    }
    catch {
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_count_subtraction' -OperationLabel 'OP3_count_subtraction' -Expression 'Convert-ToIntSafe(rawRouteCount/normalizedCount) -> subtraction' -LeftOperand $rawRouteCount -RightOperand $normalizedCount -Status 'failed' -ErrorRecord $_
        Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_count_subtraction' -ActiveOperationLabel 'OP3_count_subtraction' -ActiveExpression 'Convert-ToIntSafe(rawRouteCount/normalizedCount) -> subtraction' -OperationLabel 'OP3_count_subtraction' -Expression 'Convert-ToIntSafe(rawRouteCount/normalizedCount) -> subtraction' -LeftOperand $rawRouteCount -RightOperand $normalizedCount -VariableNames @('rawRouteCount', 'normalizedCount', 'rawRouteCountInt', 'normalizedCountInt', 'droppedDelta') -AdditionalContext @{
            counts_computed_before_failure = $aggregateComputedCounts
            stack_hint = $_.ScriptStackTrace
            route_path = ''
        }
        throw
    }

    $droppedCount = $null
    try {
        $zeroBoundary = 0
        $droppedDeltaInt = Convert-ToIntSafe -Value $droppedDelta -Default 0
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_drop_count_coerce' -OperationLabel 'OP4A_dropped_delta_to_int' -Expression 'Convert-ToIntSafe -Value $droppedDelta -Default 0' -LeftOperand $droppedDelta -RightOperand $droppedDeltaInt -Status 'ok'
        if ([int]$droppedDeltaInt -lt 0) {
            $droppedCount = 0
        }
        else {
            $droppedCount = [int]$droppedDeltaInt
        }
        $aggregateComputedCounts.dropped_count = $droppedCount
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_drop_count_math' -OperationLabel 'OP4B_dropped_count_floor_zero' -Expression 'if ($droppedDeltaInt -lt 0) { 0 } else { [int]$droppedDeltaInt }' -LeftOperand $zeroBoundary -RightOperand $droppedDeltaInt -Status 'ok'
    }
    catch {
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_drop_count_math' -OperationLabel 'OP4B_dropped_count_floor_zero' -Expression 'if ($droppedDeltaInt -lt 0) { 0 } else { [int]$droppedDeltaInt }' -LeftOperand 0 -RightOperand $droppedDelta -Status 'failed' -ErrorRecord $_
        Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_drop_count_math' -ActiveOperationLabel 'OP4B_dropped_count_floor_zero' -ActiveExpression 'if ($droppedDeltaInt -lt 0) { 0 } else { [int]$droppedDeltaInt }' -OperationLabel 'OP4B_dropped_count_floor_zero' -Expression 'if ($droppedDeltaInt -lt 0) { 0 } else { [int]$droppedDeltaInt }' -LeftOperand 0 -RightOperand $droppedDelta -VariableNames @('zeroBoundary', 'droppedDelta', 'droppedDeltaInt', 'droppedCount') -AdditionalContext @{
            counts_computed_before_failure = $aggregateComputedCounts
            raw_route_count = $rawRouteCount
            normalized_count = $normalizedCount
            stack_hint = $_.ScriptStackTrace
        }
        throw
    }

    for ($index = 0; $index -lt @($rawRoutes).Count; $index++) {
        $routePathForIndex = [string](Safe-Get -Object $routePathByIndex -Key ([string]$index) -Default '')
        Add-RouteNormalizationTracePhase -PhaseName 'drop_count_computation' -RouteIndex $index -RoutePathIfAvailable $routePathForIndex -PhaseObject ([ordered]@{
                raw_route_count = $rawRouteCount
                normalized_count = $normalizedCount
                dropped_delta = $droppedDelta
                dropped_count = $droppedCount
            }) -Status 'ok'
    }

    $normalizedRoutesOutput = $null
    $shapeWarningsOutput = $null
    try {
        if ($null -eq $normalized) {
            $normalizedRoutesOutput = @()
        }
        elseif ($normalized -is [System.Collections.Generic.List[object]]) {
            $normalizedRoutesOutput = @($normalized.ToArray())
        }
        elseif ($normalized -is [System.Collections.Generic.List[string]]) {
            $normalizedRoutesOutput = @($normalized.ToArray())
        }
        elseif ($normalized -is [System.Collections.ICollection]) {
            $normalizedRoutesOutput = @($normalized)
        }
        elseif ($normalized -is [System.Collections.IEnumerable] -and -not ($normalized -is [string])) {
            $normalizedRoutesOutput = @($normalized)
        }
        else {
            $normalizedRoutesOutput = @($normalized)
        }

        if ($null -eq $shapeWarnings) {
            $shapeWarningsOutput = @()
        }
        elseif ($shapeWarnings -is [System.Collections.Generic.List[string]]) {
            $shapeWarningsOutput = @($shapeWarnings.ToArray())
        }
        elseif ($shapeWarnings -is [System.Collections.Generic.List[object]]) {
            $shapeWarningsOutput = @($shapeWarnings | ForEach-Object {
                    if ($null -eq $_) { return }
                    [string]$_
                })
        }
        elseif ($shapeWarnings -is [System.Collections.ICollection]) {
            $shapeWarningsOutput = @($shapeWarnings | ForEach-Object {
                    if ($null -eq $_) { return }
                    [string]$_
                })
        }
        elseif ($shapeWarnings -is [System.Collections.IEnumerable] -and -not ($shapeWarnings -is [string])) {
            $shapeWarningsOutput = @($shapeWarnings | ForEach-Object {
                    if ($null -eq $_) { return }
                    [string]$_
                })
        }
        elseif ($shapeWarnings -is [string]) {
            if ([string]::IsNullOrWhiteSpace($shapeWarnings)) {
                $shapeWarningsOutput = @()
            }
            else {
                $shapeWarningsOutput = @([string]$shapeWarnings)
            }
        }
        else {
            $shapeWarningsOutput = @([string]$shapeWarnings)
        }

        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_return_materialization' -OperationLabel 'OP5A_return_output_materialize' -Expression 'normalized/shapeWarnings safe output materialization' -LeftOperand $normalized -RightOperand $normalizedRoutesOutput -Status 'ok'
    }
    catch {
        Add-RouteNormalizationAggregateTrace -PhaseName 'aggregate_return_materialization' -OperationLabel 'OP5A_return_output_materialize' -Expression 'normalized/shapeWarnings safe output materialization' -LeftOperand $normalized -RightOperand $normalizedRoutesOutput -Status 'failed' -ErrorRecord $_
        Set-RouteNormalizationForensics -FunctionName 'Normalize-LiveRoutes' -ActivePhase 'aggregate_return_materialization' -ActiveOperationLabel 'OP5A_return_output_materialize' -ActiveExpression 'normalized/shapeWarnings safe output materialization' -OperationLabel 'OP5A_return_output_materialize' -Expression 'normalized/shapeWarnings safe output materialization' -LeftOperand $normalized -RightOperand $normalizedRoutesOutput -VariableNames @('normalized', 'shapeWarnings', 'normalizedRoutesOutput', 'shapeWarningsOutput') -AdditionalContext @{
            counts_computed_before_failure = $aggregateComputedCounts
            stack_hint = $_.ScriptStackTrace
        }
        throw
    }

    return [ordered]@{
        routes = @($normalizedRoutesOutput)
        raw_count = [int](Convert-ToIntSafe -Value $rawRouteCount -Default 0)
        dropped_count = [int](Convert-ToIntSafe -Value $droppedCount -Default 0)
        warnings = @($shapeWarningsOutput)
    }
}
