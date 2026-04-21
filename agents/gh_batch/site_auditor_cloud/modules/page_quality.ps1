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

function Convert-ToPageQualityObjectArray {
    param([object]$Value)

    $operationLabel = 'PQX_helper_object_array_materialize'
    $expression = 'Convert-ToPageQualityObjectArray boundary conversion'
    try {
        if ($null -eq $Value) { return @() }
        if ($Value -is [System.Collections.Generic.List[object]]) { return [object[]]$Value.ToArray() }
        if ($Value -is [System.Collections.Generic.List[string]]) { return [object[]]$Value.ToArray() }
        if (($Value -is [System.Collections.ICollection]) -and -not ($Value -is [System.Collections.IDictionary])) {
            $output = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) {
                if ($item -is [System.Collections.Specialized.OrderedDictionary]) {
                    $output.Add([pscustomobject]$item)
                }
                else {
                    $output.Add($item)
                }
            }
            return [object[]]$output.ToArray()
        }
        if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary]) -and -not ($Value -is [pscustomobject])) {
            $output = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) {
                if ($item -is [System.Collections.Specialized.OrderedDictionary]) {
                    $output.Add([pscustomobject]$item)
                }
                else {
                    $output.Add($item)
                }
            }
            return [object[]]$output.ToArray()
        }
        return @($Value)
    }
    catch {
        Set-PageQualityForensics -FunctionName 'Convert-ToPageQualityObjectArray' -ActivePhase 'PAGE_QUALITY_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $Value -RightOperand $null -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                helper = 'Convert-ToPageQualityObjectArray'
                value_shape = Get-ObjectShapeSummary -Value $Value
                error_message = $_.Exception.Message
            })
        throw
    }
}

function Convert-ToPageQualityStringArray {
    param([object]$Value)

    $operationLabel = 'PQX_helper_string_array_materialize'
    $expression = 'Convert-ToPageQualityStringArray normalization'
    try {
        $items = Convert-ToPageQualityObjectArray -Value $Value
        $normalized = New-Object System.Collections.Generic.List[string]

        foreach ($item in $items) {
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

        return [string[]]$normalized.ToArray()
    }
    catch {
        Set-PageQualityForensics -FunctionName 'Convert-ToPageQualityStringArray' -ActivePhase 'PAGE_QUALITY_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $Value -RightOperand $null -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                helper = 'Convert-ToPageQualityStringArray'
                value_shape = Get-ObjectShapeSummary -Value $Value
                error_message = $_.Exception.Message
            })
        throw
    }
}

function Build-SitePatternSummary {
    param(
        [int]$TotalRoutes,
        [hashtable]$Rollups
    )

    $operationLabel = 'PQ7_pattern_summary_build'
    $expression = 'Build-SitePatternSummary aggregation and dominant selection'
    $pq7CombineLeftOperand = $null
    $pq7CombineRightOperand = $null
    $pq7RepeatedOutputCount = 0
    $pq7IsolatedOutputCount = 0
    $pq7RepeatedOutputType = ''
    $pq7IsolatedOutputType = ''
    try {
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

        $repeatedPatternsOutput = Convert-ToPageQualityObjectArray -Value $repeatedPatterns
        $isolatedPatternsOutput = Convert-ToPageQualityObjectArray -Value $isolatedPatterns
        $operationLabel = 'PQ7a_pattern_summary_prepare_combine_operands'
        $expression = 'Materialize repeated/isolated pattern outputs into deterministic object[] arrays'
        $pq7CombineLeftOperand = [object[]](Convert-ToPageQualityObjectArray -Value $repeatedPatternsOutput)
        $pq7CombineRightOperand = [object[]](Convert-ToPageQualityObjectArray -Value $isolatedPatternsOutput)
        $repeatedPatternsOutput = [object[]]$pq7CombineLeftOperand
        $isolatedPatternsOutput = [object[]]$pq7CombineRightOperand
        $pq7RepeatedOutputCount = @($pq7CombineLeftOperand).Count
        $pq7IsolatedOutputCount = @($pq7CombineRightOperand).Count
        $pq7RepeatedOutputType = if ($null -eq $pq7CombineLeftOperand) { '<null>' } else { $pq7CombineLeftOperand.GetType().FullName }
        $pq7IsolatedOutputType = if ($null -eq $pq7CombineRightOperand) { '<null>' } else { $pq7CombineRightOperand.GetType().FullName }

        $operationLabel = 'PQ7b_pattern_summary_combine_deterministic_array'
        $expression = 'Build deterministic combined pattern object[] without hashtable addition semantics'
        $combinedPatternList = New-Object System.Collections.Generic.List[object]
        foreach ($pattern in $pq7CombineLeftOperand) { $combinedPatternList.Add($pattern) }
        foreach ($pattern in $pq7CombineRightOperand) { $combinedPatternList.Add($pattern) }
        $combinedPatterns = Convert-ToPageQualityObjectArray -Value $combinedPatternList.ToArray()

        $operationLabel = 'PQ7c_pattern_summary_dominant_selection'
        $expression = 'Select dominant pattern from deterministic combined pattern object[]'
        $dominant = $null
        foreach ($pattern in $combinedPatterns) {
            $patternRoutesAffected = Convert-ToIntSafe -Value (Safe-Get -Object $pattern -Key 'routes_affected' -Default 0) -Default 0
            $dominantRoutesAffected = Convert-ToIntSafe -Value (Safe-Get -Object $dominant -Key 'routes_affected' -Default 0) -Default 0
            if ($null -eq $dominant -or $patternRoutesAffected -gt $dominantRoutesAffected) {
                $dominant = $pattern
            }
        }

        return @{
            repeated_patterns = $repeatedPatternsOutput
            isolated_patterns = $isolatedPatternsOutput
            repeated_pattern_count = [int]$repeatedPatterns.Count
            isolated_pattern_count = [int]$isolatedPatterns.Count
            systemic = ([int]$repeatedPatterns.Count -gt 0)
            dominant_pattern = $dominant
        }
    }
    catch {
        $leftOperand = $Rollups
        $rightOperand = $TotalRoutes
        if (($operationLabel -eq 'PQ7a_pattern_summary_prepare_combine_operands') -or
            ($operationLabel -eq 'PQ7b_pattern_summary_combine_deterministic_array') -or
            ($operationLabel -eq 'PQ7c_pattern_summary_dominant_selection')) {
            $leftOperand = $pq7CombineLeftOperand
            $rightOperand = $pq7CombineRightOperand
        }

        Set-PageQualityForensics -FunctionName 'Build-SitePatternSummary' -ActivePhase 'PAGE_QUALITY_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $leftOperand -RightOperand $rightOperand -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                total_routes = $TotalRoutes
                rollups_shape = Get-ObjectShapeSummary -Value $Rollups
                repeated_patterns_output_count = [int]$pq7RepeatedOutputCount
                isolated_patterns_output_count = [int]$pq7IsolatedOutputCount
                repeated_patterns_output_type = $pq7RepeatedOutputType
                isolated_patterns_output_type = $pq7IsolatedOutputType
                repeated_patterns_emit_shape = Get-ObjectShapeSummary -Value $pq7CombineLeftOperand
                isolated_patterns_emit_shape = Get-ObjectShapeSummary -Value $pq7CombineRightOperand
                error_message = $_.Exception.Message
            })
        throw
    }
}

function Build-PageQualityFindings {
    param([object[]]$Routes)

    $operationLabel = 'PQ1_routes_input_materialize'
    $expression = 'Convert-ToPageQualityObjectArray -Value $Routes'
    $routesInput = @()
    $pq4aRoutePath = ''
    $pq4aRouteFindings = $null
    $pq4aRouteFindingsOutput = $null
    $pq4aRouteFindingsCount = 0
    $pq4aRouteFindingsType = ''
    $pq4aRouteVerdict = ''
    $pq4aRouteContradictions = $null
    $pq4aContaminationFlags = $null
    $pq4aCurrentLeftOperand = $null
    $pq4aCurrentRightOperand = $null
    $pq4aRouteFindingsCountBeforeFailure = 0
    try {
        $routesInput = Convert-ToPageQualityObjectArray -Value $Routes
        $result = New-Object System.Collections.Generic.List[object]
        $emptyRoutes = 0
        $thinRoutes = 0
        $weakCtaRoutes = 0
        $deadEndRoutes = 0
        $contaminatedRoutes = 0
        $issueScreenshotCount = 0
        $issuesMissingEvidence = 0
        $verdictCounts = @{}

        foreach ($route in @($routesInput)) {
            $operationLabel = 'PQ2_route_flag_extraction'
            $expression = 'Route signal extraction and boolean flag derivation'
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
            $contaminationFlags = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $route -Key 'contaminationFlags' -Default @())
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
            $routeContradictions = New-Object System.Collections.Generic.List[object]
            $baseScreenshots = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $route -Key 'screenshots' -Default @())
            $issueScreenshots = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $route -Key 'issue_screenshots' -Default @())
            $base = @($baseScreenshots)
            $issue = @($issueScreenshots)

            if ($null -eq $base) { $base = @() }
            if ($null -eq $issue) { $issue = @() }

            $combined = New-Object System.Collections.Generic.List[object]

            foreach ($i in $base) {
                if ($null -ne $i) { $combined.Add($i) }
            }

            foreach ($i in $issue) {
                if ($null -ne $i) { $combined.Add($i) }
            }

            $screenshotEvidence = @(
                $combined |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Select-Object -Unique
            )
            $routeIssues = New-Object System.Collections.Generic.List[object]

            $operationLabel = 'PQ3_route_contradictions_build'
            $expression = 'Route contradiction candidate construction with explicit scalar normalization at boundary'
            $pq3PrimaryVerdict = [string]$primaryVerdict
            $pq3Thin = [bool]$thin
            $pq3WeakCta = [bool]$weakCta
            $pq3DeadEnd = [bool]$deadEnd
            $pq3Empty = [bool]$empty
            $pq3HasNav = [bool]$hasNav
            $pq3BodyTextLength = Convert-ToIntSafe -Value $bodyTextLength -Default 0
            $pq3StatusCode = Convert-ToIntSafe -Value $statusCode -Default 0
            $pq3RouteObject = Safe-Get -Object $route -Key 'Value' -Default $route
            $pq3RouteScreenshots = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $pq3RouteObject -Key 'screenshots' -Default @())
            $pq3RouteIssueScreenshots = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $pq3RouteObject -Key 'issue_screenshots' -Default @())
            $pq3RouteScreenshots = @($pq3RouteScreenshots)
            $pq3RouteIssueScreenshots = @($pq3RouteIssueScreenshots)
            $pq3RouteScreenshotCountRawSource = Safe-Get -Object $pq3RouteObject -Key 'screenshotCount' -Default $null
            $pq3RouteScreenshotCountRaw = if (($pq3RouteScreenshotCountRawSource -is [System.Collections.IEnumerable]) -and
                $pq3RouteScreenshotCountRawSource -isnot [System.Collections.IDictionary] -and
                -not ($pq3RouteScreenshotCountRawSource -is [string])) {
                ($pq3RouteScreenshotCountRawSource | Select-Object -First 1)
            }
            else {
                $pq3RouteScreenshotCountRawSource
            }
            if (($null -eq $pq3RouteScreenshotCountRaw) -or
                (($pq3RouteScreenshotCountRaw -is [System.Collections.IEnumerable]) -and
                 $pq3RouteScreenshotCountRaw -isnot [System.Collections.IDictionary] -and
                 -not ($pq3RouteScreenshotCountRaw -is [string]))) {
                $pq3RouteScreenshotCountRaw = @($pq3RouteScreenshots).Count + @($pq3RouteIssueScreenshots).Count
            }
            $routeScreenshotCount = Convert-ToIntSafe -Value $pq3RouteScreenshotCountRaw -Default 0
            $pq3RouteScreenshotCount = Convert-ToIntSafe -Value $routeScreenshotCount -Default 0
            [System.Collections.Generic.List[object]]$routeContradictionsNormalized = New-Object System.Collections.Generic.List[object]
            foreach ($routeContradictionSeed in @(Convert-ToPageQualityObjectArray -Value $routeContradictions)) {
                if ($null -eq $routeContradictionSeed) { continue }
                [void]$routeContradictionsNormalized.Add($routeContradictionSeed)
            }
            $routeContradictions = $routeContradictionsNormalized

            $isHealthyButVisuallyWeak = ($pq3PrimaryVerdict -eq 'HEALTHY') -and ($pq3Thin -or $pq3WeakCta -or $pq3DeadEnd -or ($pq3BodyTextLength -lt 250) -or ($pq3StatusCode -ge 400) -or ($pq3RouteScreenshotCount -eq 0))
            if ($isHealthyButVisuallyWeak) {
                $routeContradictions.Add([ordered]@{
                        class = 'HEALTHY_BUT_VISUALLY_WEAK'
                        scope = 'ROUTE'
                        severity = 'REVIEW'
                        evidence = [string]::Format(
                            'verdict=HEALTHY while thin={0} weak_cta={1} dead_end={2} bodyTextLength={3} status={4} screenshotCount={5}',
                            $pq3Thin,
                            $pq3WeakCta,
                            $pq3DeadEnd,
                            $pq3BodyTextLength,
                            $pq3StatusCode,
                            $pq3RouteScreenshotCount
                        )
                    })
            }

            $isNonEmptyLowValue = (-not $pq3Empty) -and ($pq3BodyTextLength -gt 120) -and ($pq3WeakCta -or $pq3DeadEnd)
            if ($isNonEmptyLowValue) {
                $routeContradictions.Add([ordered]@{
                        class = 'NON_EMPTY_BUT_LOW_VALUE'
                        scope = 'ROUTE'
                        severity = 'REVIEW'
                        evidence = [string]::Format(
                            'bodyTextLength={0} avoids EMPTY, but weak_cta={1} dead_end={2} links={3} buttonCount={4} hasNav={5}',
                            $pq3BodyTextLength,
                            $pq3WeakCta,
                            $pq3DeadEnd,
                            (Convert-ToIntSafe -Value $links -Default 0),
                            (Convert-ToIntSafe -Value $buttonCount -Default 0),
                            $pq3HasNav
                        )
                    })
            }

            if ($empty) { $emptyRoutes++ }
            if ($thin) { $thinRoutes++ }
            if ($weakCta) { $weakCtaRoutes++ }
            if ($deadEnd) { $deadEndRoutes++ }
            if ($uiContamination) { $contaminatedRoutes++ }
            if ($screenshotEvidence.Count -gt 0) { $issueScreenshotCount += $screenshotEvidence.Count }

            if ($empty) {
                $routeIssues.Add([ordered]@{
                    class = 'EMPTY_OR_NEAR_EMPTY_PAGE'
                    requires_visual_proof = $true
                    evidence_refs = @($screenshotEvidence | Select-Object -First 2)
                })
            }
            if ($uiContamination) {
                $routeIssues.Add([ordered]@{
                    class = 'OVERLAY_OR_UI_CONTAMINATION'
                    requires_visual_proof = $true
                    evidence_refs = @($screenshotEvidence | Select-Object -First 2)
                })
            }
            if ((-not $hasMain) -and (-not $hasArticle)) {
                $routeIssues.Add([ordered]@{
                    class = 'DUPLICATE_SHELL_OR_MISSING_CRITICAL_BLOCK'
                    requires_visual_proof = $true
                    evidence_refs = @($screenshotEvidence | Select-Object -First 2)
                })
            }
            if (($statusCode -ge 500) -or $normalizedText.Contains('{{') -or $normalizedText.Contains('{%')) {
                $routeIssues.Add([ordered]@{
                    class = 'BROKEN_RENDER_OR_TEMPLATE_LEAKAGE'
                    requires_visual_proof = $true
                    evidence_refs = @($screenshotEvidence | Select-Object -First 2)
                })
            }
            if ((-not $empty) -and $links -eq 0 -and $images -eq 0 -and $buttonCount -eq 0) {
                $routeIssues.Add([ordered]@{
                    class = 'SEVERE_LAYOUT_BREAK'
                    requires_visual_proof = $true
                    evidence_refs = @($screenshotEvidence | Select-Object -First 2)
                })
            }
            $operationLabel = 'PQ3B_issue_evidence_refs_materialize'
            $expression = 'Materialize issue evidence_refs into string[] for evidence coverage validation'
            foreach ($issue in @($routeIssues)) {

                if ($null -eq $issue) { continue }

                if (-not ($issue -is [System.Collections.IDictionary] -or $issue -is [pscustomobject])) {
                    continue
                }

                $rawEvidenceRefs = Safe-Get -Object $issue -Key 'evidence_refs' -Default @()

                if ($null -eq $rawEvidenceRefs) {
                    $rawEvidenceRefs = @()
                }

                $normalizedEvidenceRefs = Convert-ToPageQualityObjectArray -Value $rawEvidenceRefs

                $ev = Convert-ToPageQualityStringArray -Value $normalizedEvidenceRefs

                if ($ev.Count -eq 0) { $issuesMissingEvidence++ }
            }

            $primaryVerdictKey = [string]$primaryVerdict
            if ([string]::IsNullOrWhiteSpace($primaryVerdictKey)) {
                $primaryVerdictKey = 'UNKNOWN'
            }

            if (-not $verdictCounts.ContainsKey($primaryVerdictKey)) {
                $verdictCounts[$primaryVerdictKey] = 0
            }

            $verdictCounts[$primaryVerdictKey] = [int]$verdictCounts[$primaryVerdictKey] + 1

            $pq4aRoutePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
            $operationLabel = 'PQ4A1_route_findings_list_init'
            $expression = 'Initialize local deterministic route findings list as Generic.List[string]'
            $routeFindings = New-Object System.Collections.Generic.List[string]

            $operationLabel = 'PQ4A2_route_findings_list_populate'
            $expression = 'Populate local route findings list from route signals and contradiction candidates'
            $routeContradictionsLocal = Convert-ToPageQualityObjectArray -Value $routeContradictions
            $contaminationFlagsLocal = Convert-ToPageQualityStringArray -Value $contaminationFlags
            $pq4aRouteContradictions = $routeContradictionsLocal
            $pq4aContaminationFlags = $contaminationFlagsLocal

            $operationLabel = 'PQ4A2a_add_empty_flag_line'
            $expression = 'Add empty-route finding line when empty route signal is true'
            $pq4aCurrentLeftOperand = $empty
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            if ($empty) { $routeFindings.Add('Route has empty or near-empty visible content.') }

            $operationLabel = 'PQ4A2b_add_thin_flag_line'
            $expression = 'Add thin-route finding line when thin route signal is true'
            $pq4aCurrentLeftOperand = $thin
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            if ($thin) { $routeFindings.Add('Route content is thin and likely underdeveloped.') }

            $operationLabel = 'PQ4A2c_add_weak_cta_line'
            $expression = 'Add weak-cta finding line when weak_cta route signal is true'
            $pq4aCurrentLeftOperand = $weakCta
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            if ($weakCta) { $routeFindings.Add('Route lacks clear CTA affordances.') }

            $operationLabel = 'PQ4A2d_add_dead_end_line'
            $expression = 'Add dead-end finding line when dead_end route signal is true'
            $pq4aCurrentLeftOperand = $deadEnd
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            if ($deadEnd) { $routeFindings.Add('Route appears to be a dead-end with limited onward navigation.') }

            $operationLabel = 'PQ4A2e_add_contamination_line'
            $expression = 'Add ui contamination finding line using deterministic local contamination flags'
            $pq4aCurrentLeftOperand = $contaminationFlagsLocal
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            if ($uiContamination) { $routeFindings.Add("UI contamination markers detected: $($contaminationFlagsLocal -join ', ').") }

            $operationLabel = 'PQ4A2f_iterate_route_contradictions'
            $expression = 'Iterate deterministic local contradiction candidates and append contradiction finding lines'
            $pq4aCurrentLeftOperand = $routeContradictionsLocal
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            foreach ($candidate in $routeContradictionsLocal) {
                $routeFindings.Add("Contradiction candidate [$([string](Safe-Get -Object $candidate -Key 'class' -Default 'UNKNOWN'))]: $([string](Safe-Get -Object $candidate -Key 'evidence' -Default ''))")
            }

            $operationLabel = 'PQ4A2g_add_primary_verdict_line'
            $expression = 'Add primary verdict class finding line'
            $pq4aCurrentLeftOperand = $primaryVerdict
            $pq4aCurrentRightOperand = $routeFindings
            $pq4aRouteFindingsCountBeforeFailure = [int]$routeFindings.Count
            $routeFindings.Add("Primary verdict class: $primaryVerdict")
            $pq4aRouteFindings = $routeFindings
            $pq4aRouteFindingsCount = [int]$routeFindings.Count
            $pq4aRouteFindingsType = if ($null -eq $routeFindings) { '' } else { [string]$routeFindings.GetType().FullName }
            $pq4aRouteVerdict = $primaryVerdict
            $pq4aRouteContradictions = $routeContradictionsLocal
            $pq4aContaminationFlags = $contaminationFlagsLocal

            $operationLabel = 'PQ4A3_route_findings_fastpath_toarray'
            $expression = 'Use local deterministic fast-path when routeFindings is Generic.List[string]'
            if (@($routeFindings).Count -eq 0) {
                $routeFindingsOutput = @()
            }
            elseif ($routeFindings -is [System.Collections.Generic.List[string]]) {
                $routeFindingsOutput = [string[]]$routeFindings.ToArray()
            }
            elseif ($routeFindings -is [string[]]) {
                $routeFindingsOutput = [string[]]$routeFindings
            }
            else {
                $operationLabel = 'PQ4A4_route_findings_fallback_string_array'
                $expression = 'Fallback conversion of route findings to string[] only when fast-paths are not applicable'
                $routeFindingsOutput = Convert-ToPageQualityStringArray -Value $routeFindings
            }
            $pq4aRouteFindingsOutput = $routeFindingsOutput

            $operationLabel = 'PQ4A5_route_output_shape_normalization'
            $expression = 'Normalize final route findings/issues collections to concrete arrays before output assignment'
            $routeFindings = @($routeFindingsOutput)
            $routeIssues = @($routeIssues)
            $routeFindingsOutput = [object[]]$routeFindings

            $operationLabel = 'PQ4B_route_contradictions_output_object_array'
            $expression = 'Materialize route contradiction candidates into object[] without fragile rematerialization when already array'
            $routeContradictionsSource = $routeContradictions
            if ($routeContradictionsSource -is [object[]]) {
                $routeContradictionsOutput = [object[]]$routeContradictionsSource
            }
            else {
                $routeContradictionsOutput = Convert-ToPageQualityObjectArray -Value $routeContradictionsSource
            }

            $operationLabel = 'PQ4C_contamination_flags_output_string_array'
            $expression = 'Materialize contamination flags into string[] output'
            $contaminationFlagsOutput = Convert-ToPageQualityStringArray -Value $contaminationFlags

            $operationLabel = 'PQ4D_route_result_add'
            $expression = 'Append route evaluation object to result list'
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
                findings = $routeFindingsOutput
                h1Count = $h1Count
                buttonCount = $buttonCount
                hasMain = $hasMain
                hasArticle = $hasArticle
                hasNav = $hasNav
                hasFooter = $hasFooter
                visibleTextSample = $visibleTextSample
                contaminationFlags = $contaminationFlagsOutput
                contradiction_candidates = $routeContradictionsOutput
                screenshots = @($baseScreenshots)
                issue_screenshots = @($issueScreenshots)
                issues = [object[]]$routeIssues
            })
        }

        $operationLabel = 'PQ6_rollup_build'
        $expression = 'Create page-quality rollup counters and verdict counts'
        $rollups = @{
            empty_routes = [int]$emptyRoutes
            thin_routes = [int]$thinRoutes
            weak_cta_routes = [int]$weakCtaRoutes
            dead_end_routes = [int]$deadEndRoutes
            contaminated_routes = [int]$contaminatedRoutes
            issue_screenshots = [int]$issueScreenshotCount
            issues_missing_evidence = [int]$issuesMissingEvidence
            verdict_counts = $verdictCounts
        }

        $operationLabel = 'PQ7_pattern_summary_build'
        $expression = 'Build-SitePatternSummary -TotalRoutes @($routesInput).Count -Rollups $rollups'
        $patternSummary = Build-SitePatternSummary -TotalRoutes @($routesInput).Count -Rollups $rollups
        $operationLabel = 'PQ4E_route_details_output_materialize'
        $expression = 'Materialize final route_details object[] output'
        $routeDetailsOutput = Convert-ToPageQualityObjectArray -Value $result

        return @{
            route_details = $routeDetailsOutput
            rollups = $rollups
            pattern_summary = $patternSummary
        }
    }
    catch {
        $leftOperand = $Routes
        $rightOperand = $null
        if (($operationLabel -eq 'PQ4A1_route_findings_list_init') -or
            ($operationLabel -like 'PQ4A2*') -or
            ($operationLabel -eq 'PQ4A3_route_findings_fastpath_toarray') -or
            ($operationLabel -eq 'PQ4A4_route_findings_fallback_string_array')) {
            $leftOperand = if ($null -ne $pq4aCurrentLeftOperand) { $pq4aCurrentLeftOperand } else { $pq4aRouteFindings }
            $rightOperand = if ($null -ne $pq4aCurrentRightOperand) { $pq4aCurrentRightOperand } else { $pq4aRouteFindingsOutput }
        }
        elseif ($operationLabel -eq 'PQ4B_route_contradictions_output_object_array') {
            $leftOperand = $pq4aRouteContradictions
            $rightOperand = $null
        }
        elseif ($operationLabel -eq 'PQ4C_contamination_flags_output_string_array') {
            $leftOperand = $pq4aContaminationFlags
            $rightOperand = $null
        }

        Set-PageQualityForensics -FunctionName 'Build-PageQualityFindings' -ActivePhase 'PAGE_QUALITY_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $leftOperand -RightOperand $rightOperand -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                route_count_sample = @($routesInput).Count
                route_path = $pq4aRoutePath
                route_findings_count = [int]$pq4aRouteFindingsCount
                route_findings_count_before_failure = [int]$pq4aRouteFindingsCountBeforeFailure
                route_findings_type = $pq4aRouteFindingsType
                route_verdict = $pq4aRouteVerdict
                primaryVerdict = $pq4aRouteVerdict
                operation_label = $operationLabel
                expression = $expression
                error_message = $_.Exception.Message
            })
        throw
    }
}
