param(
    [string]$MODE = 'REPO'
)

Write-Host "AGENT_VERSION=V5_FINAL_FIX"
if ($true) {
    Write-Host "AGENT_VERSION=V5_FINAL_FIX"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DecisionBuildStamp = 'DBUILD_FORENSIC_V2'
Write-Host "DECISION_BUILD_STAMP: $script:DecisionBuildStamp"

. "$PSScriptRoot/modules/util_io.ps1"
. "$PSScriptRoot/modules/util_convert.ps1"
. "$PSScriptRoot/modules/util_debug.ps1"
. "$PSScriptRoot/modules/bootstrap.ps1"
. "$PSScriptRoot/modules/source_audit.ps1"
. "$PSScriptRoot/modules/route_normalization_forensics.ps1"
. "$PSScriptRoot/modules/page_quality_forensics.ps1"
. "$PSScriptRoot/modules/page_quality.ps1"
. "$PSScriptRoot/modules/route_normalization.ps1"
. "$PSScriptRoot/modules/decision_contradictions.ps1"
. "$PSScriptRoot/modules/decision_diagnosis.ps1"
. "$PSScriptRoot/modules/decision_remediation.ps1"
. "$PSScriptRoot/modules/decision_closeout.ps1"
. "$PSScriptRoot/modules/decision_build.ps1"

$bootstrapContext = Initialize-SiteAuditorBootstrapContext -ScriptRoot $PSScriptRoot -Workspace $env:GITHUB_WORKSPACE -ProcessId $PID
$base = [string]$bootstrapContext.base
$outboxDir = [string]$bootstrapContext.outboxDir
$reportsDir = [string]$bootstrapContext.reportsDir
$runtimeDir = [string]$bootstrapContext.runtimeDir
$zipWorkRoot = [string]$bootstrapContext.zipWorkRoot
$timestamp = [string]$bootstrapContext.timestamp
$runStartedAt = [string]$bootstrapContext.runStartedAt
$runFinishedAt = $bootstrapContext.runFinishedAt
$runId = [string]$bootstrapContext.runId
$currentStage = [string]$bootstrapContext.currentStage
$lastSuccessStage = [string]$bootstrapContext.lastSuccessStage
$status = [string]$bootstrapContext.status
$failureReason = $bootstrapContext.failureReason
$reportFiles = $bootstrapContext.reportFiles

function Set-DecisionForensics {
    param(
        [string]$FunctionName,
        [string]$ActivePhase = 'DECISION_BUILD',
        [string]$ActiveOperationLabel = '',
        [string]$ActiveExpression = '',
        [object]$LeftOperand = $null,
        [object]$RightOperand = $null,
        [object]$AdditionalContext = $null,
        [string]$StackHintIfAvailable = ''
    )

    $leftType = if ($null -eq $LeftOperand) { '<null>' } else { $LeftOperand.GetType().FullName }
    $rightType = if ($null -eq $RightOperand) { '<null>' } else { $RightOperand.GetType().FullName }

    $stackHint = $StackHintIfAvailable
    if ([string]::IsNullOrWhiteSpace($stackHint) -and $null -ne $AdditionalContext) {
        $stackHint = [string](Safe-Get -Object $AdditionalContext -Key 'stack_hint' -Default '')
    }

    $global:DecisionForensics = [ordered]@{
        failure_stage = 'DECISION_BUILD'
        function_name = $FunctionName
        activePhase = if ([string]::IsNullOrWhiteSpace($ActivePhase)) { 'DECISION_BUILD' } else { $ActivePhase }
        activeOperationLabel = if ([string]::IsNullOrWhiteSpace($ActiveOperationLabel)) { '' } else { $ActiveOperationLabel }
        activeExpression = if ([string]::IsNullOrWhiteSpace($ActiveExpression)) { '' } else { $ActiveExpression }
        left_type = $leftType
        right_type = $rightType
        left_value_sample = Get-DebugValueSample -Value $LeftOperand
        right_value_sample = Get-DebugValueSample -Value $RightOperand
        stack_hint_if_available = if ([string]::IsNullOrWhiteSpace($stackHint)) { '' } else { [string]$stackHint }
        additional_context = if ($null -eq $AdditionalContext) { @{} } else { $AdditionalContext }
    }
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
        foreach ($entry in @($Object.GetEnumerator())) {
            $candidateKey = Safe-Get -Object $entry -Key 'Key' -Default $null
            if ($null -eq $candidateKey) { continue }

            $candidateKeyText = $null
            $keyText = [string]$Key
            try {
                $candidateKeyText = [string]$candidateKey
            }
            catch {
                Set-RouteNormalizationForensics -FunctionName 'Safe-Get' -Expression '[string]$candidateKey' -LeftOperand $candidateKey -RightOperand $Key -RouteContext $Object -AdditionalContext @{
                    operation = 'dictionary_key_string_cast'
                    entry_shape = Get-ObjectShapeSummary -Value $entry
                    stack_hint = $_.ScriptStackTrace
                }
                throw
            }

            try {
                if ($candidateKeyText -eq $keyText) {
                    return (Safe-Get -Object $entry -Key 'Value' -Default $Default)
                }
            }
            catch {
                Set-RouteNormalizationForensics -FunctionName 'Safe-Get' -Expression '$candidateKeyText -eq $keyText' -LeftOperand $candidateKeyText -RightOperand $keyText -RouteContext $Object -AdditionalContext @{
                    operation = 'dictionary_key_compare'
                    original_left_type = $candidateKey.GetType().FullName
                    entry_shape = Get-ObjectShapeSummary -Value $entry
                    stack_hint = $_.ScriptStackTrace
                }
                throw
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

function Convert-ToDecisionWarningStringArray {
    param([object]$Value)

    $result = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Value) {
        return @()
    }

    try {
        foreach ($item in $Value) {

            if ($null -eq $item) { continue }

            $text = [string]$item

            if ([string]::IsNullOrWhiteSpace($text)) { continue }

            $result.Add($text)
        }
    }
    catch {
        $text = [string]$Value

        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $result.Add($text)
        }
    }

    return @($result.ToArray())
}

function Normalize-ProductCloseout {
    param([object]$Value)

    $default = [ordered]@{
        class = 'BLOCKED_BY_UNKNOWN'
        reason = 'Product closeout classification was not generated.'
        confidence = 'low'
        checks = @()
        evidence = @()
    }

    if ($null -eq $Value) { return $default }

    $node = $Value
    if ($node -is [System.Collections.IEnumerable] -and
        -not ($node -is [string]) -and
        -not ($node -is [System.Collections.IDictionary]) -and
        -not ($node -is [PSCustomObject])) {
        $items = Convert-ToObjectArraySafe -Value $node
        if ($items.Count -le 0) { return $default }
        $node = $items[0]
    }

    if (-not ($node -is [System.Collections.IDictionary]) -and -not ($node -is [PSCustomObject])) {
        return $default
    }

    $classification = [string](Safe-Get -Object $node -Key 'class' -Default 'BLOCKED_BY_UNKNOWN')
    if ([string]::IsNullOrWhiteSpace($classification)) { $classification = 'BLOCKED_BY_UNKNOWN' }

    $reason = [string](Safe-Get -Object $node -Key 'reason' -Default 'Product closeout classification was not generated.')
    if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'Product closeout classification was not generated.' }

    $confidence = [string](Safe-Get -Object $node -Key 'confidence' -Default 'low')
    if ($confidence -notin @('high', 'medium', 'low')) { $confidence = 'low' }

    $checksRaw = Convert-ToObjectArraySafe -Value (Safe-Get -Object $node -Key 'checks' -Default @())
    $checks = @(
        foreach ($check in @($checksRaw)) {
            if ($null -eq $check) { continue }

            if ($check -is [string]) {
                $text = [string]$check
            }
            elseif ($check -is [System.Collections.IDictionary] -or $check -is [pscustomobject]) {
                $checkNode = Convert-ToHashtableSafe -Value $check
                $text = [string](Safe-Get -Object $checkNode -Key 'label' -Default (Safe-Get -Object $checkNode -Key 'name' -Default (Safe-Get -Object $checkNode -Key 'message' -Default '')))
            }
            else {
                $text = [string]$check
            }

            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $text
            }
        }
    )

    $evidence = Convert-ToStringArraySafe -Value (Safe-Get -Object $node -Key 'evidence' -Default @())

    $result = @{
        class = [string]$classification
        reason = [string]$reason
        confidence = [string]$confidence
        checks = @($checks)
        evidence = @($evidence)
    }
    return $result
}

function Get-ProductStatusString {
    param(
        [object]$ProductStatus,
        [string]$Default = 'UNKNOWN'
    )

    $defaultStatus = [string]$Default
    if ([string]::IsNullOrWhiteSpace($defaultStatus)) { $defaultStatus = 'UNKNOWN' }

    if ($null -eq $ProductStatus) { return $defaultStatus }

    if ($ProductStatus -is [string]) {
        $statusText = [string]$ProductStatus
        if ([string]::IsNullOrWhiteSpace($statusText)) { return $defaultStatus }
        return $statusText
    }

    if ($ProductStatus -is [System.Collections.IDictionary] -or $ProductStatus -is [PSCustomObject]) {
        $statusText = [string](Safe-Get -Object $ProductStatus -Key 'status' -Default $defaultStatus)
        if ([string]::IsNullOrWhiteSpace($statusText)) { return $defaultStatus }
        return $statusText
    }

    return $defaultStatus
}

function Normalize-ProductCloseoutForOutput {
    param([object]$Value)

    $node = Normalize-ProductCloseout -Value $Value
    $checksRaw = Convert-ToObjectArraySafe -Value (Safe-Get -Object $node -Key 'checks' -Default @())
    $checks = @(
        foreach ($check in @($checksRaw)) {
            if ($null -eq $check) { continue }

            if ($check -is [System.Collections.IDictionary] -or $check -is [PSCustomObject]) {
                $node = Convert-ToHashtableSafe -Value $check
                $text = [string](Safe-Get -Object $node -Key 'name' -Default (Safe-Get -Object $node -Key 'detail' -Default 'check'))
            }
            else {
                $text = [string]$check
            }

            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $text
            }
        }
    )

    $evidence = Convert-ToStringArraySafe -Value (Safe-Get -Object $node -Key 'evidence' -Default @())

    return [ordered]@{
        class = [string](Safe-Get -Object $node -Key 'class' -Default 'BLOCKED_BY_UNKNOWN')
        reason = [string](Safe-Get -Object $node -Key 'reason' -Default 'Product closeout classification was not generated.')
        confidence = [string](Safe-Get -Object $node -Key 'confidence' -Default 'low')
        checks = @($checks)
        evidence = @($evidence)
    }
}

function Normalize-AuditResult {
    param([hashtable]$AuditResult)

    if ($null -eq $AuditResult) {
        $AuditResult = @{}
    }

    $AuditResult['source'] = New-SourceLayer -Overrides (Safe-Get -Object $AuditResult -Key 'source' -Default @{})
    $AuditResult['live'] = New-LiveLayer -Overrides (Safe-Get -Object $AuditResult -Key 'live' -Default @{})

    if (-not $AuditResult.ContainsKey('required_inputs') -or $null -eq $AuditResult['required_inputs']) {
        $AuditResult['required_inputs'] = @()
    }

    return $AuditResult
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
        if ($null -eq $global:RouteNormalizationTrace) {
            $global:RouteNormalizationTrace = @()
        }
        if ($null -eq $global:RouteNormalizationAggregateTrace) {
            $global:RouteNormalizationAggregateTrace = @()
        }
        $firstFailingAggregateEntry = Get-FirstFailingAggregateTraceEntry
        Write-JsonFile -Path (Join-Path $reportsDir 'route_normalization_trace.json') -Data ([ordered]@{
                failure_stage = ''
                trace_phases = @($global:RouteNormalizationTrace)
                aggregate_trace = @($global:RouteNormalizationAggregateTrace)
                aggregate = [ordered]@{
                    first_failing_operation_label = [string](Safe-Get -Object $firstFailingAggregateEntry -Key 'operation_label' -Default '')
                    first_failing_phase_name = [string](Safe-Get -Object $firstFailingAggregateEntry -Key 'phase_name' -Default '')
                    operations = @($global:RouteNormalizationAggregateTrace)
                }
            })
        $reportFiles.Add('reports/route_normalization_trace.json')
        $routes = Convert-ToObjectArraySafe -Value (Safe-Get -Object $normalizedRoutesData -Key 'routes' -Default @())
        $fallbackRouteDetails = @($routes)
        $fallbackRouteCount = @($routes).Count
        $shapeWarnings = Convert-ToStringArraySafe -Value (Safe-Get -Object $normalizedRoutesData -Key 'warnings' -Default @())
        $droppedCount = [int](Safe-Get -Object $normalizedRoutesData -Key 'dropped_count' -Default 0)

        $liveStage = 'ROUTE_MERGE'
        $errored = @($routes | Where-Object {
                $statusValue = Safe-Get -Object $_ -Key 'status' -Default 'error'
                $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
                $statusText = ([string]$statusValue).Trim().ToLowerInvariant()
                ($statusText -eq 'error') -or ($statusCode -ge 400)
            })
        $healthy = @($routes | Where-Object {
                $statusValue = Safe-Get -Object $_ -Key 'status' -Default 'error'
                $statusCode = Convert-ToIntSafe -Value $statusValue -Default -1
                $statusText = ([string]$statusValue).Trim().ToLowerInvariant()
                ($statusText -ne 'error') -and ($statusCode -ge 0) -and ($statusCode -lt 400)
            })
        $totalShots = 0
        foreach ($routeItem in @($routes)) {
            $totalShots += Convert-ToIntSafe -Value (Safe-Get -Object $routeItem -Key 'screenshotCount' -Default 0) -Default 0
        }

        $liveStage = 'PAGE_QUALITY_BUILD'
        $global:PageQualityForensics = $null
        $routeDetailsAndRollups = Build-PageQualityFindings -Routes $routes
        $routeDetails = @($routeDetailsAndRollups.route_details)
        $rollups = $routeDetailsAndRollups.rollups
        $patternSummary = Safe-Get -Object $routeDetailsAndRollups -Key 'pattern_summary' -Default @{}
        $coverageSummary = Build-EvidenceCoverageSummary -Routes $routes
        $routesWithCanonicalCoverage = @($routes | Where-Object {
                $shotMap = Safe-Get -Object $_ -Key 'screenshot_map' -Default @{}
                -not [string]::IsNullOrWhiteSpace([string](Safe-Get -Object $shotMap -Key 'top' -Default '')) -and
                -not [string]::IsNullOrWhiteSpace([string](Safe-Get -Object $shotMap -Key 'mid' -Default '')) -and
                -not [string]::IsNullOrWhiteSpace([string](Safe-Get -Object $shotMap -Key 'bottom' -Default ''))
            })
        $issueScreenshotCount = [int](Safe-Get -Object $rollups -Key 'issue_screenshots' -Default 0)
        $issuesMissingEvidence = [int](Safe-Get -Object $rollups -Key 'issues_missing_evidence' -Default 0)
        $routesTotal = [int]@($routes).Count
        $routesCaptured = [int]@($routesWithCanonicalCoverage).Count
        $coverageScore = 0
        if ($routesTotal -gt 0) {
            $coverageScore = [int][Math]::Round((($routesCaptured / [double]$routesTotal) * 100), 0)
        }

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
        if ($issuesMissingEvidence -gt 0) {
            $pageQualityStatus = 'PARTIAL'
            $warnings.Add("ISSUE_EVIDENCE: $issuesMissingEvidence issue(s) are missing screenshot evidence references.")
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
        $findings.Add("Evidence richness: $([string](Safe-Get -Object $coverageSummary -Key 'evidence_richness' -Default 'SPARSE')).")

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
                evidence_coverage = $coverageSummary
                raw_route_entries = [int](Safe-Get -Object $normalizedRoutesData -Key 'raw_count' -Default 0)
                normalized_route_entries = @($routes).Count
                dropped_route_entries = $droppedCount
                visual_coverage = [ordered]@{
                    routes_total = $routesTotal
                    routes_captured = $routesCaptured
                    issue_screenshots = $issueScreenshotCount
                    coverage_score = $coverageScore
                }
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
        $failureDetailed = $failure
        $routeNormalizationDebug = $null
        if ($liveStage -eq 'PAGE_QUALITY_BUILD') {
            if ($null -eq $global:PageQualityForensics) {
                Set-PageQualityForensics -FunctionName 'Invoke-LiveAudit' -ActivePhase 'PAGE_QUALITY_BUILD' -ActiveOperationLabel 'PQ_UNATTRIBUTED_RUNTIME_FAILURE' -ActiveExpression 'Build-PageQualityFindings -Routes $routes' -LeftOperand $routes -RightOperand $null -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                        failure_message = $failure
                        note = 'PAGE_QUALITY_BUILD failed before helper-level forensic state was populated.'
                    })
            }

            $pageQualityDebug = [ordered]@{
                forensic = $global:PageQualityForensics
                failure_message = $failure
                timestamp = (Get-Date).ToString('o')
            }
            try {
                Write-JsonFile -Path (Join-Path $reportsDir 'page_quality_debug.json') -Data $pageQualityDebug
                $reportFiles.Add('reports/page_quality_debug.json')
            }
            catch {
            }

            $pqFunction = [string](Safe-Get -Object $global:PageQualityForensics -Key 'function_name' -Default '')
            $pqOperation = [string](Safe-Get -Object $global:PageQualityForensics -Key 'activeOperationLabel' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($pqOperation)) {
                $failureDetailed = "$failure [PAGE_QUALITY_BUILD/$pqFunction/$pqOperation]"
            }
        }
        if ($liveStage -eq 'ROUTE_NORMALIZATION') {
            try {
                if ($null -eq $global:RouteNormalizationTrace) {
                    $global:RouteNormalizationTrace = @()
                }
                if ($null -eq $global:RouteNormalizationAggregateTrace) {
                    $global:RouteNormalizationAggregateTrace = @()
                }
                $firstFailingAggregateEntry = Get-FirstFailingAggregateTraceEntry
                Write-JsonFile -Path (Join-Path $reportsDir 'route_normalization_trace.json') -Data ([ordered]@{
                        failure_stage = 'ROUTE_NORMALIZATION'
                        trace_phases = @($global:RouteNormalizationTrace)
                        aggregate_trace = @($global:RouteNormalizationAggregateTrace)
                        aggregate = [ordered]@{
                            first_failing_operation_label = [string](Safe-Get -Object $firstFailingAggregateEntry -Key 'operation_label' -Default '')
                            first_failing_phase_name = [string](Safe-Get -Object $firstFailingAggregateEntry -Key 'phase_name' -Default '')
                            operations = @($global:RouteNormalizationAggregateTrace)
                        }
                    })
                $reportFiles.Add('reports/route_normalization_trace.json')
            }
            catch {
            }
            if ($null -ne $global:RouteNormalizationForensics) {
                $routeNormalizationDebug = $global:RouteNormalizationForensics
            }
            else {
                $tracePhases = Convert-ToObjectArraySafe -Value $global:RouteNormalizationTrace
                $aggregateTrace = Convert-ToObjectArraySafe -Value $global:RouteNormalizationAggregateTrace
                if (@($tracePhases).Count -gt 0 -or @($aggregateTrace).Count -gt 0) {
                    $firstFailingTrace = Get-FirstFailingAggregateTraceEntry
                    $routeNormalizationDebug = [ordered]@{
                        function_name = 'Normalize-LiveRoutes'
                        operation_label = [string](Safe-Get -Object $firstFailingTrace -Key 'operation_label' -Default 'OP_TRACE_ONLY_FAILURE')
                        expression = 'trace/aggregate evidence captured before failure completion'
                        active_phase = [string](Safe-Get -Object $firstFailingTrace -Key 'phase_name' -Default 'route_normalization_trace_available')
                        degraded_run = $true
                        failure_message = $failure
                        additional_context = [ordered]@{
                            trace_phase_count = @($tracePhases).Count
                            aggregate_trace_count = @($aggregateTrace).Count
                        }
                    }
                }
                else {
                    $routeNormalizationDebug = New-RouteNormalizationFallbackDebug -StackHint $_.ScriptStackTrace -FailureMessage $failure
                }
            }
            try {
                Write-JsonFile -Path (Join-Path $reportsDir 'route_normalization_debug.json') -Data $routeNormalizationDebug
                $reportFiles.Add('reports/route_normalization_debug.json')
            }
            catch {
            }
        }
        return (New-LiveLayer -Overrides @{
            enabled = $true
            required = $false
            root = $BaseUrl
            base_url = $BaseUrl
            summary = @{
                page_quality_status = 'NOT_EVALUATED'
                failure_stage = $liveStage
                evaluation_error = $failureDetailed
                degraded_run = $true
                total_routes = [int]$fallbackRouteCount
                route_normalization_debug = if ($null -eq $routeNormalizationDebug) { @{} } else { $routeNormalizationDebug }
            }
            findings = @("Live audit failed at stage ${liveStage}: $failureDetailed")
            warnings = @("Live audit encountered an execution error at stage ${liveStage}: $failureDetailed")
            route_details = @($fallbackRouteDetails)
            ok = $false
        })
    }
}










function Write-SelfRepairArtifacts {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [string]$FailureReason,
        [string]$CurrentStage,
        [string]$LastSuccessStage
    )

    Ensure-Dir $reportsDir
    Ensure-Dir $outboxDir

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    $runReportPath = Join-Path $reportsDir 'RUN_REPORT.json'

    $auditResultNode = @{}
    if (Test-Path $auditResultPath -PathType Leaf) {
        try {
            $parsedAudit = Get-Content -Path $auditResultPath -Raw | ConvertFrom-Json -Depth 64 -AsHashtable
            if ($parsedAudit -is [System.Collections.IDictionary]) {
                $auditResultNode = $parsedAudit
            }
        }
        catch {
            $auditResultNode = @{}
        }
    }

    $runReportNode = @{}
    if (Test-Path $runReportPath -PathType Leaf) {
        try {
            $parsedRunReport = Get-Content -Path $runReportPath -Raw | ConvertFrom-Json -Depth 64 -AsHashtable
            if ($parsedRunReport -is [System.Collections.IDictionary]) {
                $runReportNode = $parsedRunReport
            }
        }
        catch {
            $runReportNode = @{}
        }
    }

    $decisionNode = Convert-ToHashtableSafe -Value (Safe-Get -Object $auditResultNode -Key 'decision' -Default @{})
    $repairHint = Convert-ToHashtableSafe -Value (Safe-Get -Object $decisionNode -Key 'repair_hint' -Default @{})
    if (@($repairHint.Keys).Count -eq 0) {
        $repairHint = [ordered]@{
            target_file = 'agents/gh_batch/site_auditor_cloud/agent.ps1'
            broken_block = if ([string]::IsNullOrWhiteSpace([string]$CurrentStage)) { 'UNKNOWN_BLOCK' } else { [string]$CurrentStage }
            reason = if ([string]::IsNullOrWhiteSpace([string]$FailureReason)) { 'No explicit failure reason captured.' } else { [string]$FailureReason }
            next_action = if ($FinalStatus -eq 'PASS') { 'No repair action required.' } else { "Inspect stage '$CurrentStage', update the target block, then rerun the same mode." }
            failed_stage = if ([string]::IsNullOrWhiteSpace([string]$CurrentStage)) { 'UNKNOWN_STAGE' } else { [string]$CurrentStage }
            mode = [string]$ResolvedMode
            missing_inputs = @()
            priority_routes = @()
        }
    }

    $priorityRoutes = Convert-ToStringArraySafe -Value (Safe-Get -Object $repairHint -Key 'priority_routes' -Default @())
    $coreProblem = [string](Safe-Get -Object $decisionNode -Key 'core_problem' -Default '')
    if ([string]::IsNullOrWhiteSpace($coreProblem)) {
        $coreProblem = [string](Safe-Get -Object $repairHint -Key 'reason' -Default 'Repair reason unavailable.')
    }

    $failedNode = [string](Safe-Get -Object (Safe-Get -Object $runReportNode -Key 'key_evidence_excerpts' -Default @{}) -Key 'decision_build_failed_node' -Default '')
    if ([string]::IsNullOrWhiteSpace($failedNode)) {
        $failedNode = [string](Safe-Get -Object (Safe-Get -Object $runReportNode -Key 'key_evidence_excerpts' -Default @{}) -Key 'failure_node' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($failedNode)) { $failedNode = [string]$CurrentStage }

    $loopState = if ($FinalStatus -eq 'PASS') { 'STABLE' } elseif ($FinalStatus -eq 'PARTIAL') { 'READY_FOR_REPAIR_PASS' } else { 'REPAIR_REQUIRED' }
    $canPrepareRepairPack = ($FinalStatus -ne 'PASS')
    $canApplyPatchDirectly = $false

    $selfRepairPlan = [ordered]@{
        schema_version = '1.0'
        run_id = $runId
        generated_at = (Get-Date).ToString('o')
        mode = [string]$ResolvedMode
        final_status = [string]$FinalStatus
        loop_state = $loopState
        can_prepare_repair_pack = [bool]$canPrepareRepairPack
        can_apply_patch_directly = [bool]$canApplyPatchDirectly
        failed_node = $failedNode
        last_success_stage = [string]$LastSuccessStage
        core_problem = $coreProblem
        repair_hint = $repairHint
        repair_contract = [ordered]@{
            task_id = "SELF_REPAIR_$($runId)"
            objective = if ($FinalStatus -eq 'PASS') { 'Keep current baseline stable.' } else { "Repair failing node '$failedNode' and rerun the same mode." }
            input = [ordered]@{
                target_file = [string](Safe-Get -Object $repairHint -Key 'target_file' -Default 'agents/gh_batch/site_auditor_cloud/agent.ps1')
                broken_block = [string](Safe-Get -Object $repairHint -Key 'broken_block' -Default 'UNKNOWN_BLOCK')
                reason = [string](Safe-Get -Object $repairHint -Key 'reason' -Default $coreProblem)
                next_action = [string](Safe-Get -Object $repairHint -Key 'next_action' -Default '')
                priority_routes = @($priorityRoutes | Select-Object -First 5)
            }
            output = [ordered]@{
                expected_change = [string](Safe-Get -Object $repairHint -Key 'expected_change' -Default 'Updated target block and a new rerun artifact set with lower severity or PASS.')
                validation = [string](Safe-Get -Object $repairHint -Key 'validation' -Default 'Workflow rerun must remove or downgrade the current failed node.')
                fail_mode = [string](Safe-Get -Object $repairHint -Key 'fail_mode' -Default 'Failed node remains unchanged after rerun.')
            }
        }
    }

    $selfRepairContext = [ordered]@{
        mode = [string]$ResolvedMode
        final_status = [string]$FinalStatus
        failure_reason = if ([string]::IsNullOrWhiteSpace([string]$FailureReason)) { '' } else { [string]$FailureReason }
        current_stage = [string]$CurrentStage
        last_success_stage = [string]$LastSuccessStage
        audit_result_path = 'reports/audit_result.json'
        run_report_path = 'reports/RUN_REPORT.json'
        truth_sources = @(
            'reports/audit_result.json',
            'reports/RUN_REPORT.json',
            'reports/FAILURE_SUMMARY.json',
            'reports/visual_manifest.json'
        )
    }

    Write-JsonFile -Path (Join-Path $reportsDir 'SELF_REPAIR_PLAN.json') -Data $selfRepairPlan
    Write-JsonFile -Path (Join-Path $reportsDir 'SELF_REPAIR_CONTEXT.json') -Data $selfRepairContext

    $nextText = if ($FinalStatus -eq 'PASS') {
        'Run is stable. Keep monitoring and rerun only after meaningful changes.'
    }
    else {
        [string](Safe-Get -Object $repairHint -Key 'next_action' -Default "Inspect '$failedNode', patch the target block, then rerun.")
    }

    $targetFileText = [string](Safe-Get -Object $repairHint -Key 'target_file' -Default 'agents/gh_batch/site_auditor_cloud/agent.ps1')
    $brokenBlockText = [string](Safe-Get -Object $repairHint -Key 'broken_block' -Default 'UNKNOWN_BLOCK')
    $reasonText = [string](Safe-Get -Object $repairHint -Key 'reason' -Default $coreProblem)

    Write-TextFile -Path (Join-Path $outboxDir '20_SELF_REPAIR_NEXT.txt') -Lines @(
        "MODE: $ResolvedMode",
        "FINAL STATUS: $FinalStatus",
        "LOOP STATE: $loopState",
        "TARGET FILE: $targetFileText",
        "BROKEN BLOCK: $brokenBlockText",
        "FAILED NODE: $failedNode",
        "REASON: $reasonText",
        "NEXT ACTION: $nextText",
        "PRIORITY ROUTES: $((@($priorityRoutes | Select-Object -First 5) -join ', '))",
        "SELF REPAIR PLAN: reports/SELF_REPAIR_PLAN.json",
        "SELF REPAIR CONTEXT: reports/SELF_REPAIR_CONTEXT.json"
    )

    if (-not ($reportFiles.Contains('reports/SELF_REPAIR_PLAN.json'))) { $reportFiles.Add('reports/SELF_REPAIR_PLAN.json') }
    if (-not ($reportFiles.Contains('reports/SELF_REPAIR_CONTEXT.json'))) { $reportFiles.Add('reports/SELF_REPAIR_CONTEXT.json') }
    if (-not ($reportFiles.Contains('outbox/20_SELF_REPAIR_NEXT.txt'))) { $reportFiles.Add('outbox/20_SELF_REPAIR_NEXT.txt') }
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
    $contradictionSummary = Safe-Get -Object $liveSummary -Key 'contradiction_summary' -Default @{}
    $siteDiagnosis = Safe-Get -Object $Decision -Key 'site_diagnosis' -Default @{}
    $maturityReadiness = Safe-Get -Object $Decision -Key 'maturity_readiness' -Default @{}
    $auditorBaseline = Safe-Get -Object $Decision -Key 'auditor_baseline' -Default @{}
    $remediationPackage = Safe-Get -Object $Decision -Key 'remediation_package' -Default @{}
    $productCloseout = Normalize-ProductCloseout -Value (Safe-Get -Object $Decision -Key 'product_closeout' -Default $null)
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
    $confidenceLimitersSafe = @($confidenceLimiters)
    $limiterText = if ($confidenceLimitersSafe.Count -gt 0) { $confidenceLimitersSafe -join ' ' } else { 'none; enabled deterministic checks completed.' }
    $contradictionTotal = [int](Safe-Get -Object $contradictionSummary -Key 'total_candidates' -Default 0)
    $contradictionClassCounts = Safe-Get -Object $contradictionSummary -Key 'class_counts' -Default @{}
    $contradictionClassLine = 'none'
    if ($contradictionTotal -gt 0) {
        $contradictionClassLine = @(
            @($contradictionClassCounts.Keys | Sort-Object | ForEach-Object { [ordered]@{ class = [string]$_; count = [int]$contradictionClassCounts[$_] } }) |
                Sort-Object -Property @{Expression = 'count'; Descending = $true }, @{Expression = 'class'; Descending = $false } |
                Select-Object -First 4 |
                ForEach-Object { "$($_.class)=$($_.count)" }
        ) -join ', '
    }

    $dominantPatternLine = 'mixed pattern / no dominant pattern'
    if ($null -ne $dominantPattern) {
        $label = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default 'unknown')
        $scope = [string](Safe-Get -Object $dominantPattern -Key 'scope' -Default 'ISOLATED')
        $count = [int](Safe-Get -Object $dominantPattern -Key 'routes_affected' -Default 0)
        $dominantPatternLine = "$label ($scope, $count route(s))"
    }

    $scoredRoutes = @(
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
                $reasons = @()
                if ($empty) { $reasons += 'empty' }
                if ($contaminated) { $reasons += 'trust contamination' }
                if ($thin) { $reasons += 'thin content' }
                if ($weakCta) { $reasons += 'weak CTA' }
                if ($deadEnd) { $reasons += 'dead-end flow' }
                if ($status -ge 400 -or $status -eq 0) { $reasons += "status $status" }
                if ($verdict -eq 'HEALTHY' -and ($bodyTextLength -lt 250 -or $status -ge 400 -or $status -eq 0)) { $reasons += 'healthy verdict but weak evidence signals' }
                $reasonsSafe = @(
                    foreach ($reason in @($reasons)) {
                        if ($null -ne $reason) {
                            $reasonText = [string]$reason
                            if (-not [string]::IsNullOrWhiteSpace($reasonText)) { $reasonText }
                        }
                    }
                )

                [pscustomobject]@{
                    route_path = [string]$routePath
                    score      = [int]$score
                    verdict    = [string]$verdict
                    reasons    = @($reasonsSafe)
                }
            }
        }
    )

    $suspiciousRouteLines = New-Object System.Collections.Generic.List[string]
    if ($scoredRoutes.Count -gt 0) {
        foreach ($item in @($scoredRoutes | Sort-Object -Property @{Expression = 'score'; Descending = $true }, @{Expression = 'route_path'; Descending = $false } | Select-Object -First 6)) {
            $itemReasonsSafe = @(
                foreach ($r in @($item.reasons)) {
                    if ($null -ne $r) {
                        $rt = [string]$r
                        if (-not [string]::IsNullOrWhiteSpace($rt)) { $rt }
                    }
                }
            )
            $reasonText = if ($itemReasonsSafe.Count -gt 0) { $itemReasonsSafe -join ', ' } else { 'review required' }
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

        $pathsSafe = @($paths)
        if ($pathsSafe.Count -eq 0) { return 'none' }
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
    $dominantRoutesSafe = @($dominantRoutes)

    $screenshotPlan = New-Object System.Collections.Generic.List[string]
    $screenshotPlan.Add("- Start with highest-risk routes: $(& $formatRouteSet $worstRouteSet 3).")
    if ($dominantRoutesSafe.Count -gt 0) {
        $screenshotPlan.Add("- Validate dominant pattern routes early ($dominantPatternLine): $(& $formatRouteSet $dominantRoutes 3).")
    }
    $suspiciousHealthyRoutesSafe = @($suspiciousHealthyRoutes)
    if ($suspiciousHealthyRoutesSafe.Count -gt 0) {
        $screenshotPlan.Add("- Compare suspicious HEALTHY routes against weak routes to catch false-positive health labels: $(& $formatRouteSet $suspiciousHealthyRoutes 3).")
    }
    if ($runState -in @('partial', 'degraded', 'failed')) {
        $screenshotPlan.Add("- Run is $runState; increase screenshot-first validation because deterministic rollups may be incomplete.")
    }
    $screenshotPlanSafe = @($screenshotPlan)
    if ($screenshotPlanSafe.Count -eq 0) {
        $screenshotPlan.Add('- No deterministic high-risk cluster available; review one route per verdict class from visual_manifest.')
    }

    $comparisonGroups = New-Object System.Collections.Generic.List[string]
    $comparisonGroups.Add("- Worst vs best: [$(& $formatRouteSet $worstRouteSet 2)] vs [$(& $formatRouteSet $bestHealthyRoutes 2)].")
    if ($suspiciousHealthyRoutesSafe.Count -gt 0) {
        $comparisonGroups.Add("- Suspicious HEALTHY vs clearly weak: [$(& $formatRouteSet $suspiciousHealthyRoutes 2)] vs [$(& $formatRouteSet $worstRouteSet 2)].")
    }
    $contaminatedRoutesSafe = @($contaminatedRoutes)
    if ($contaminatedRoutesSafe.Count -gt 0) {
        $comparisonGroups.Add("- Trust contamination contrast: contaminated [$(& $formatRouteSet $contaminatedRoutes 2)] vs non-contaminated [$(& $formatRouteSet $cleanRoutes 2)].")
    }
    if ($dominantRoutesSafe.Count -gt 0) {
        $comparisonGroups.Add("- Same dominant verdict-pattern cluster: [$(& $formatRouteSet $dominantRoutes 3)].")
    }

    $repoVsLivePrompts = @(
        '- Do repo/source route structures and templates support what each live route claims to be?',
        '- Where live pages look thin/shell-like, does source/repo show missing content wiring or only presentation weakness?',
        '- Do navigation and CTA elements in source/repo map to what screenshots show, or are critical conversion paths absent live?',
        '- Does each priority route screenshot look like a product-ready page, or only a framework shell despite expected repo structure?'
    )

    $contradictionHotspots = New-Object System.Collections.Generic.List[string]
    if ($suspiciousHealthyRoutesSafe.Count -gt 0) {
        $contradictionHotspots.Add("- HEALTHY-but-suspicious routes need screenshot verification: $(& $formatRouteSet $suspiciousHealthyRoutes 3).")
    }
    if ($contaminatedRoutesSafe.Count -gt 0) {
        $contradictionHotspots.Add("- Summary may look acceptable while contamination is visually obvious on: $(& $formatRouteSet $contaminatedRoutes 3).")
    }
    if ($runState -in @('partial', 'degraded', 'failed')) {
        $contradictionHotspots.Add("- Deterministic wording may understate live severity because run state is $runState; verify screenshot evidence before trusting aggregate text.")
    }
    $worstRouteSetSafe = @($worstRouteSet)
    if ($dominantRoutesSafe.Count -gt 0 -and $worstRouteSetSafe.Count -gt 0) {
        $contradictionHotspots.Add("- Confirm dominant pattern claim by comparing [$(& $formatRouteSet $dominantRoutes 2)] against highest-risk outliers [$(& $formatRouteSet $worstRouteSet 2)].")
    }
    $contradictionHotspots.Add('- Routes classified weak may still show real user value; if screenshots contradict class labels, annotate exact mismatch and route.')
    if ($contradictionTotal -gt 0) {
        $contradictionHotspots.Add("- Deterministic contradiction layer flagged $contradictionTotal candidate(s): $contradictionClassLine.")
    }

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
    $healthyLowTextRoutes = @($routeDetails | Where-Object { [string](Safe-Get -Object $_ -Key 'verdict_class' -Default '') -eq 'HEALTHY' -and ([int](Safe-Get -Object $_ -Key 'bodyTextLength' -Default 0) -lt 250) })
    if ($healthyLowTextRoutes.Count -gt 0) {
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
        "- Site diagnosis: $([string](Safe-Get -Object $siteDiagnosis -Key 'class' -Default 'UNKNOWN'))",
        "- Diagnosis reason: $([string](Safe-Get -Object $siteDiagnosis -Key 'reason' -Default 'none'))",
        "- Diagnosis confidence: $([string](Safe-Get -Object $siteDiagnosis -Key 'confidence' -Default 'LOW'))",
        "- Maturity/readiness: $([string](Safe-Get -Object $maturityReadiness -Key 'class' -Default 'NOT_READY'))",
        "- Maturity reason: $([string](Safe-Get -Object $maturityReadiness -Key 'reason' -Default 'none'))",
        "- Maturity confidence: $([string](Safe-Get -Object $maturityReadiness -Key 'confidence' -Default 'LOW'))",
        "- Auditor baseline: $([string](Safe-Get -Object $auditorBaseline -Key 'class' -Default 'BLOCKED_BY_UNKNOWN'))",
        "- Baseline reason: $([string](Safe-Get -Object $auditorBaseline -Key 'reason' -Default 'none'))",
        "- Baseline confidence: $([string](Safe-Get -Object $auditorBaseline -Key 'confidence' -Default 'LOW'))",
        "- Product closeout: $([string](Safe-Get -Object $productCloseout -Key 'class' -Default 'BLOCKED_BY_UNKNOWN'))",
        "- Product closeout reason: $([string](Safe-Get -Object $productCloseout -Key 'reason' -Default 'none'))",
        "- Contradiction candidates: $contradictionTotal ($contradictionClassLine)",
        "- Clean-state check: $([string](Safe-Get -Object $Decision -Key 'clean_state' -Default 'NOT_CLEAN'))",
        '',
        'PRIMARY REMEDIATION PACKAGE',
        "- PACKAGE_NAME: $([string](Safe-Get -Object $remediationPackage -Key 'package_name' -Default 'MIXED_RECOVERY_PACKAGE'))",
        "- PACKAGE_GOAL: $([string](Safe-Get -Object $remediationPackage -Key 'package_goal' -Default 'none'))",
        "- PRIMARY_TARGETS: $((@(Safe-Get -Object $remediationPackage -Key 'primary_targets' -Default @()) | Select-Object -First 5) -join ', ')",
        "- WHY_FIRST: $([string](Safe-Get -Object $remediationPackage -Key 'why_first' -Default 'none'))",
        "- SUCCESS_CHECK: $([string](Safe-Get -Object $remediationPackage -Key 'success_check' -Default 'none'))",
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
        '- Prioritize contradiction classes from the deterministic layer before final interpretation.',
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

function Get-LayerStatusLabel {
    param(
        [object]$Layer,
        [string]$DisabledLabel = 'OFF'
    )

    if (-not (Convert-ToBoolSafe -Value (Safe-Get -Object $Layer -Key 'enabled' -Default $false))) { return $DisabledLabel }
    if (Convert-ToBoolSafe -Value (Safe-Get -Object $Layer -Key 'ok' -Default $false)) { return 'PASS' }
    return 'FAIL'
}

function Add-ArtifactManifestItem {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [string]$Path,
        [string]$ArtifactType,
        [string]$Purpose,
        [string]$Priority
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    foreach ($existing in @($Items)) {
        if ([string]$existing.path -eq $Path) { return }
    }

    $Items.Add([ordered]@{
        path = $Path
        artifact_type = $ArtifactType
        purpose = $Purpose
        priority_for_operator = $Priority
    })
}

function Convert-ToObjectArrayOrEmpty {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        return @([string]$Value)
    }

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        return ,$Value
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            [void]$items.Add($item)
        }
        return @($items.ToArray())
    }

    try {
        return @($Value)
    }
    catch {
        return ,$Value
    }
}

function Get-TruthBackedConfirmedStages {
    param(
        [string]$SourceStatus,
        [string]$LiveStatus,
        [string]$PageQualityStatus,
        [string]$LastSuccessStage,
        [string]$CurrentStage
    )

    $confirmed = New-Object System.Collections.Generic.List[string]
    if ($SourceStatus -eq 'PASS') { $confirmed.Add('SOURCE_AUDIT') }
    if ($LiveStatus -eq 'PASS') { $confirmed.Add('LIVE_AUDIT') }
    if ($PageQualityStatus -notin @('NOT_EVALUATED', 'PARTIAL')) { $confirmed.Add('PAGE_QUALITY_BUILD') }

    $lastSuccess = [string]$LastSuccessStage
    if (-not [string]::IsNullOrWhiteSpace($lastSuccess) -and ($confirmed -notcontains $lastSuccess)) {
        $confirmed.Add($lastSuccess)
    }

    $failedStage = [string]$CurrentStage
    if (-not [string]::IsNullOrWhiteSpace($failedStage)) {
        $filtered = New-Object System.Collections.Generic.List[string]
        foreach ($stage in @($confirmed)) {
            if ([string]::IsNullOrWhiteSpace([string]$stage)) { continue }
            if ([string]$stage -eq $failedStage) { continue }
            if ($filtered -contains [string]$stage) { continue }
            $filtered.Add([string]$stage)
        }
        return @($filtered)
    }

    return @($confirmed)
}

function Resolve-FailureCoreFacts {
    param(
        [object]$ErrorRecord = $null,
        [string]$FailureReason = '',
        [string]$DefaultMessage = 'SITE_AUDITOR runtime failure.'
    )

    $errorRecordSafe = if ($null -eq $ErrorRecord) { $global:AuditError } else { $ErrorRecord }
    $exception = $null
    if ($null -ne $errorRecordSafe) {
        $exception = Safe-Get -Object $errorRecordSafe -Key 'Exception' -Default $null
    }

    $message = [string]$FailureReason
    if ([string]::IsNullOrWhiteSpace($message) -and $null -ne $exception) {
        $message = [string](Safe-Get -Object $exception -Key 'Message' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($message) -and $null -ne $errorRecordSafe) {
        $message = [string](Safe-Get -Object $errorRecordSafe -Key 'FullyQualifiedErrorId' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($message) -and $null -ne $errorRecordSafe) {
        try { $message = [string]($errorRecordSafe | Out-String) } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$DefaultMessage
    }

    $errorClass = ''
    if ($null -ne $exception -and $exception.GetType) {
        $errorClass = [string]$exception.GetType().FullName
    }
    if ([string]::IsNullOrWhiteSpace($errorClass) -and $null -ne $errorRecordSafe) {
        $errorClass = [string](Safe-Get -Object $errorRecordSafe -Key 'FullyQualifiedErrorId' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($errorClass) -and -not [string]::IsNullOrWhiteSpace($message)) {
        $errorClass = 'RUNTIME_FAILURE'
    }

    $stackHint = ''
    if ($null -ne $errorRecordSafe) {
        $stackHint = [string](Safe-Get -Object $errorRecordSafe -Key 'ScriptStackTrace' -Default '')
    }

    return [ordered]@{
        error_message = [string]$message
        error_class = [string]$errorClass
        stack_hint_if_available = [string]$stackHint
    }
}

function Resolve-FailureStageForOutput {
    param(
        [string]$CandidateFailureStage = '',
        [string]$CurrentStage = '',
        [string]$LastSuccessStage = ''
    )

    $candidate = [string]$CandidateFailureStage
    $current = [string]$CurrentStage
    $lastSuccess = [string]$LastSuccessStage

    if (-not [string]::IsNullOrWhiteSpace($current) -and $current -eq 'OPERATOR_OUTPUT_CONTRACT') {
        if ($lastSuccess -in @('DECISION_BUILD', 'INPUT_VALIDATION')) {
            return 'OPERATOR_OUTPUT_CONTRACT'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        return $candidate
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        return $current
    }

    return 'RUNTIME_FAILURE'
}

function Get-FallbackTruthEvidence {
    param(
        [string]$AuditResultPath,
        [string]$FailureReason,
        [string]$CurrentStage,
        [string]$LastSuccessStage
    )

    $auditResult = @{}
    if (-not [string]::IsNullOrWhiteSpace($AuditResultPath) -and (Test-Path $AuditResultPath -PathType Leaf)) {
        try {
            $parsedAudit = Get-Content -Path $AuditResultPath -Raw | ConvertFrom-Json -Depth 32
            if ($null -ne $parsedAudit) { $auditResult = $parsedAudit }
        }
        catch {
            $auditResult = @{}
        }
    }

    $sourceLayer = Safe-Get -Object $auditResult -Key 'source' -Default @{}
    $liveLayer = Safe-Get -Object $auditResult -Key 'live' -Default @{}
    $liveSummary = Safe-Get -Object $liveLayer -Key 'summary' -Default @{}
    $sourceSummary = Safe-Get -Object $sourceLayer -Key 'summary' -Default @{}

    $productStatusDetail = Safe-Get -Object $auditResult -Key 'product_status_detail' -Default @{}
    $productStatus = Get-ProductStatusString -ProductStatus (Safe-Get -Object $auditResult -Key 'product_status' -Default $null) -Default 'UNKNOWN'
    if ($productStatus -eq 'UNKNOWN') {
        $productStatus = Get-ProductStatusString -ProductStatus $productStatusDetail -Default 'UNKNOWN'
    }
    $productReason = [string](Safe-Get -Object $productStatusDetail -Key 'reason' -Default '')
    $productActions = Convert-ToStringArraySafe -Value (
        Safe-Get -Object $auditResult -Key 'product_actions' -Default (
            Safe-Get -Object $productStatusDetail -Key 'actions' -Default @()
        )
    )

    if ([string]::IsNullOrWhiteSpace($productStatus)) {
        $productStatus = 'NEEDS_FIX'
    }

    if ([string]::IsNullOrWhiteSpace($productReason)) {
        $productReason = 'Page quality build did not produce classification'
    }

    if (-not $productActions -or @($productActions).Count -eq 0) {
        $productActions = @(
            'Fix critical UI contamination issues',
            'Add decision clarity to entry pages',
            'Establish clear action paths for user'
        )
    }

    $sourceStatus = Get-LayerStatusLabel -Layer $sourceLayer -DisabledLabel 'UNKNOWN'
    $liveStatus = Get-LayerStatusLabel -Layer $liveLayer -DisabledLabel 'UNKNOWN'

    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    if ([string]::IsNullOrWhiteSpace($pageQualityStatus)) { $pageQualityStatus = 'NOT_EVALUATED' }

    $failureStageCandidate = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default '')
    $failureStage = Resolve-FailureStageForOutput -CandidateFailureStage $failureStageCandidate -CurrentStage $CurrentStage -LastSuccessStage $LastSuccessStage

    $confirmedStages = Get-TruthBackedConfirmedStages -SourceStatus $sourceStatus -LiveStatus $liveStatus -PageQualityStatus $pageQualityStatus -LastSuccessStage $LastSuccessStage -CurrentStage $CurrentStage

    $truthSources = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($AuditResultPath) -and (Test-Path $AuditResultPath -PathType Leaf)) {
        $truthSources.Add('reports/audit_result.json')
    }
    $routeTracePath = Join-Path $reportsDir 'route_normalization_trace.json'
    if (Test-Path $routeTracePath -PathType Leaf) {
        $truthSources.Add('reports/route_normalization_trace.json')
    }

    $failureCore = Resolve-FailureCoreFacts -FailureReason $FailureReason
    $errorMessage = [string](Safe-Get -Object $failureCore -Key 'error_message' -Default '')
    $errorClass = [string](Safe-Get -Object $failureCore -Key 'error_class' -Default '')

    $blocker = [string]$errorMessage
    if ([string]::IsNullOrWhiteSpace($blocker)) { $blocker = 'Unknown fallback failure.' }

    return [ordered]@{
        source_status = $sourceStatus
        live_status = $liveStatus
        page_quality_status = $pageQualityStatus
        product_status = $productStatus
        product_reason = [string]$productReason
        product_actions = @($productActions)
        repo_summary_status = [string](Safe-Get -Object $sourceSummary -Key 'status' -Default 'UNKNOWN')
        failure_stage = $failureStage
        error_message = $errorMessage
        error_class = $errorClass
        failure_node = [string]$failureStage
        blocker = $blocker
        confirmed_passing_stages = @($confirmedStages)
        primary_truth_sources = @($truthSources)
    }
}

function Write-RunForensicsReports {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [hashtable]$AuditResult,
        [hashtable]$Decision,
        [string]$FailureReason,
        [string]$CurrentStage,
        [string]$LastSuccessStage,
        [string]$RunFinishedAt
    )

    $liveSummary = Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'summary' -Default @{}
    $sourceStatus = Get-LayerStatusLabel -Layer (Safe-Get -Object $AuditResult -Key 'source' -Default @{})
    $liveStatus = Get-LayerStatusLabel -Layer (Safe-Get -Object $AuditResult -Key 'live' -Default @{})
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')

    $productStatusRaw = Safe-Get -Object $AuditResult -Key 'product_status' -Default $null
    $productStatusDetail = Safe-Get -Object $AuditResult -Key 'product_status_detail' -Default (Safe-Get -Object $Decision -Key 'product_status' -Default @{})

    $productStatus = Get-ProductStatusString -ProductStatus $productStatusRaw -Default 'UNKNOWN'
    if ($productStatus -eq 'UNKNOWN') {
        $productStatus = Get-ProductStatusString -ProductStatus $productStatusDetail -Default 'UNKNOWN'
    }
    $productReason = [string](Safe-Get -Object $productStatusDetail -Key 'reason' -Default '')
    $productActions = Convert-ToStringArraySafe -Value (
        Safe-Get -Object $AuditResult -Key 'product_actions' -Default (
            Safe-Get -Object $Decision -Key 'do_next' -Default @()
        )
    )

    if ([string]::IsNullOrWhiteSpace($productStatus)) {
        $productStatus = 'NEEDS_FIX'
    }

    if ([string]::IsNullOrWhiteSpace($productReason)) {
        $productReason = 'Page quality build did not produce classification'
    }

    if (-not $productActions -or @($productActions).Count -eq 0) {
        $productActions = @(
            'Fix critical UI contamination issues',
            'Add decision clarity to entry pages',
            'Establish clear action paths for user'
        )
    }

    $sourceSummary = Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'source' -Default @{}) -Key 'summary' -Default @{}
    $repoSummaryStatus = [string](Safe-Get -Object $sourceSummary -Key 'status' -Default '')

    $failedStageCandidate = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default '')
    $failedStage = Resolve-FailureStageForOutput -CandidateFailureStage $failedStageCandidate -CurrentStage $CurrentStage -LastSuccessStage $LastSuccessStage
    if ([string]::IsNullOrWhiteSpace($failedStage) -and $null -ne $global:DecisionForensics) {
        $failedStage = [string](Safe-Get -Object $global:DecisionForensics -Key 'failure_stage' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($failedStage) -and $null -ne $global:PageQualityForensics) {
        $failedStage = [string](Safe-Get -Object $global:PageQualityForensics -Key 'failure_stage' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($failedStage)) {
        $failedStage = [string]$CurrentStage
    }

    $doNextList = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next' -Default @())
    $nextMove = [string]($doNextList | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($nextMove)) {
        if ($FinalStatus -eq 'PASS') {
            $nextMove = 'No technical repair node remains. Continue with normal monitoring cadence.'
        }
        else {
            $nextMove = "Inspect failed node '$failedStage' and remediate the blocker before rerun."
        }
    }

    $repairHint = Convert-ToHashtableSafe -Value (Safe-Get -Object $Decision -Key 'repair_hint' -Default @{})
    $executiveSummary = if ($FinalStatus -eq 'PASS') {
        'Run completed with PASS status; outputs are usable and no repair node remains.'
    }
    elseif ($FinalStatus -eq 'PARTIAL') {
        "Run completed with PARTIAL status; some outputs are usable but repair is required at $failedStage."
    }
    else {
        "Run completed with FAIL status; repair is required at $failedStage before output can be trusted."
    }

    $artifactItems = New-Object System.Collections.Generic.List[object]
    $artifactHints = @{
        'reports/audit_result.json' = @{ type = 'truth_audit'; purpose = 'Primary structured source/live/decision truth.'; priority = 'high' }
        'reports/run_manifest.json' = @{ type = 'run_manifest'; purpose = 'Lists run outputs and metadata.'; priority = 'high' }
        'outbox/REPORT.txt' = @{ type = 'operator_report'; purpose = 'Legacy operator summary output.'; priority = 'medium' }
        'reports/11A_EXECUTIVE_SUMMARY.txt' = @{ type = 'summary'; purpose = 'Human executive summary.'; priority = 'medium' }
        'reports/12A_META_AUDIT_BRIEF.txt' = @{ type = 'meta_brief'; purpose = 'Analyst handoff brief.'; priority = 'medium' }
        'reports/HOW_TO_FIX.json' = @{ type = 'remediation'; purpose = 'Top issues and priority actions.'; priority = 'high' }
        'reports/REMEDIATION_PACKAGE.json' = @{ type = 'remediation_package'; purpose = 'Ordered remediation package.'; priority = 'high' }
        'reports/RUN_REPORT.txt' = @{ type = 'run_report_text'; purpose = 'Top-level operator-ready forensic report.'; priority = 'high' }
        'reports/RUN_REPORT.json' = @{ type = 'run_report_json'; purpose = 'Machine-readable run report contract.'; priority = 'high' }
        'reports/ARTIFACT_MANIFEST.json' = @{ type = 'artifact_manifest'; purpose = 'Artifact inventory with priorities and purposes.'; priority = 'high' }
        'reports/FAILURE_SUMMARY.json' = @{ type = 'failure_summary'; purpose = 'Structured fail/partial summary for automation.'; priority = 'high' }
        'reports/SUCCESS_SUMMARY.json' = @{ type = 'success_summary'; purpose = 'Structured success summary for automation.'; priority = 'medium' }
        'reports/decision_debug.json' = @{ type = 'decision_debug'; purpose = 'DECISION_BUILD forensic boundary details for exact failing node recovery.'; priority = 'high' }
    }

    foreach ($path in (Convert-ToObjectArrayOrEmpty -Value $reportFiles)) {
        $hint = Safe-Get -Object $artifactHints -Key $path -Default $null
        if ($null -ne $hint) {
            Add-ArtifactManifestItem -Items $artifactItems -Path $path -ArtifactType ([string]$hint.type) -Purpose ([string]$hint.purpose) -Priority ([string]$hint.priority)
        }
        else {
            Add-ArtifactManifestItem -Items $artifactItems -Path $path -ArtifactType 'report' -Purpose 'Supporting SITE_AUDITOR output artifact.' -Priority 'low'
        }
    }

    Add-ArtifactManifestItem -Items $artifactItems -Path 'outbox/REPORT.txt' -ArtifactType 'operator_report' -Purpose 'Legacy operator summary output.' -Priority 'medium'
    Add-ArtifactManifestItem -Items $artifactItems -Path 'outbox/DONE.ok' -ArtifactType 'run_marker' -Purpose 'Run pass marker file.' -Priority 'low'
    Add-ArtifactManifestItem -Items $artifactItems -Path 'outbox/DONE.fail' -ArtifactType 'run_marker' -Purpose 'Run fail marker file.' -Priority 'low'

    $artifactItemsSafe = @(
        foreach ($item in (Convert-ToObjectArrayOrEmpty -Value $artifactItems)) {
            if ($null -eq $item) { continue }
            $node = Convert-ToHashtableSafe -Value $item
            if (@($node.Keys).Count -eq 0) { continue }

            [ordered]@{
                path = [string](Safe-Get -Object $node -Key 'path' -Default '')
                artifact_type = [string](Safe-Get -Object $node -Key 'artifact_type' -Default 'report')
                purpose = [string](Safe-Get -Object $node -Key 'purpose' -Default '')
                priority_for_operator = [string](Safe-Get -Object $node -Key 'priority_for_operator' -Default 'low')
            }
        }
    )
    $artifactItemsCount = [int]$artifactItemsSafe.Count
    $usablePartialArtifacts = ($artifactItemsCount -gt 0)
    $primaryTruthSafe = @(
        foreach ($artifact in $artifactItemsSafe) {
            $artifactNode = Convert-ToHashtableSafe -Value $artifact
            if ([string](Safe-Get -Object $artifactNode -Key 'priority_for_operator' -Default '') -ne 'high') { continue }
            $artifactPath = [string](Safe-Get -Object $artifactNode -Key 'path' -Default '')
            if ([string]::IsNullOrWhiteSpace($artifactPath)) { continue }
            $artifactPath
        }
    )

    $confirmedPassingStagesBuilder = New-Object System.Collections.Generic.List[string]
    if ($sourceStatus -eq 'PASS') { $confirmedPassingStagesBuilder.Add('SOURCE_AUDIT') }
    if ($liveStatus -eq 'PASS') { $confirmedPassingStagesBuilder.Add('LIVE_AUDIT') }
    if ($pageQualityStatus -notin @('NOT_EVALUATED', 'PARTIAL')) { $confirmedPassingStagesBuilder.Add('PAGE_QUALITY_BUILD') }
    if ($FinalStatus -eq 'PASS') { $confirmedPassingStagesBuilder.Add('OPERATOR_OUTPUT_CONTRACT') }
    $confirmedPassingStagesSafe = @(
        foreach ($stageName in (Convert-ToObjectArrayOrEmpty -Value $confirmedPassingStagesBuilder)) {
            $stageText = [string]$stageName
            if ([string]::IsNullOrWhiteSpace($stageText)) { continue }
            $stageText
        }
    )

    $decisionBuildFailedNode = ''
    if ($null -ne $global:DecisionForensics) {
        $dfFailureStage = [string](Safe-Get -Object $global:DecisionForensics -Key 'failure_stage' -Default 'DECISION_BUILD')
        $dfFunction = [string](Safe-Get -Object $global:DecisionForensics -Key 'function_name' -Default '')
        $dfOperation = [string](Safe-Get -Object $global:DecisionForensics -Key 'activeOperationLabel' -Default '')
        $decisionNodeParts = New-Object System.Collections.Generic.List[string]
        foreach ($nodePart in @($dfFailureStage, $dfFunction, $dfOperation)) {
            $nodePartText = [string]$nodePart
            if ([string]::IsNullOrWhiteSpace($nodePartText)) { continue }
            $decisionNodeParts.Add($nodePartText)
        }
        if ($decisionNodeParts.Count -gt 0) {
            $decisionBuildFailedNode = [string]::Join('/', @($decisionNodeParts.ToArray()))
        }

        $decisionDebugPath = Join-Path $reportsDir 'decision_debug.json'
        Write-JsonFile -Path $decisionDebugPath -Data ([ordered]@{
            run_id = $runId
            generated_at = $RunFinishedAt
            final_status = $FinalStatus
            final_stage = $CurrentStage
            decision_build_failed_node = $decisionBuildFailedNode
            decision_forensics = $global:DecisionForensics
        })
        if (-not ($reportFiles.Contains('reports/decision_debug.json'))) {
            $reportFiles.Add('reports/decision_debug.json')
        }
    }
    if (($failedStage -eq 'OPERATOR_OUTPUT_CONTRACT' -or [string]::IsNullOrWhiteSpace($failedStage) -or $failedStage -eq 'RUNTIME_FAILURE') -and -not [string]::IsNullOrWhiteSpace($decisionBuildFailedNode)) {
        $failedStage = [string]$decisionBuildFailedNode
    }
    if (($failedStage -eq 'OPERATOR_OUTPUT_CONTRACT' -or [string]::IsNullOrWhiteSpace($failedStage) -or $failedStage -eq 'RUNTIME_FAILURE') -and $null -ne $global:PageQualityForensics) {
        $pqFailureStage = [string](Safe-Get -Object $global:PageQualityForensics -Key 'failure_stage' -Default '')
        $pqFunction = [string](Safe-Get -Object $global:PageQualityForensics -Key 'function_name' -Default '')
        $pqOperation = [string](Safe-Get -Object $global:PageQualityForensics -Key 'activeOperationLabel' -Default '')
        $pqNodeParts = New-Object System.Collections.Generic.List[string]
        foreach ($nodePart in @($pqFailureStage, $pqFunction, $pqOperation)) {
            $nodePartText = [string]$nodePart
            if ([string]::IsNullOrWhiteSpace($nodePartText)) { continue }
            $pqNodeParts.Add($nodePartText)
        }
        if ($pqNodeParts.Count -gt 0) {
            $failedStage = [string]::Join('/', @($pqNodeParts.ToArray()))
        }
    }

    $repoSummaryOut = [string]$repoSummaryStatus
    if ([string]::IsNullOrWhiteSpace($repoSummaryOut)) { $repoSummaryOut = 'UNKNOWN' }

    $failureCore = Resolve-FailureCoreFacts -FailureReason $FailureReason
    $errorMessage = [string](Safe-Get -Object $failureCore -Key 'error_message' -Default '')
    $errorClassText = [string](Safe-Get -Object $failureCore -Key 'error_class' -Default '')

    $targetValue = [string]$env:TARGET_REPO_PATH
    if ([string]::IsNullOrWhiteSpace($targetValue)) {
        $targetValue = [string](Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'base_url' -Default 'UNKNOWN_TARGET')
    }

    $inputValidationStatusText = if ($LastSuccessStage -in @('INPUT_VALIDATION', 'DECISION_BUILD', 'OPERATOR_OUTPUT_CONTRACT', 'COMPLETE')) { 'PASS' } else { 'UNKNOWN' }
    $decisionBuildStatusText = if ($LastSuccessStage -in @('DECISION_BUILD', 'OPERATOR_OUTPUT_CONTRACT', 'COMPLETE')) { 'PASS' } else { 'FAIL_OR_SKIPPED' }
    $operatorContractStatusText = if ($CurrentStage -eq 'COMPLETE' -or $LastSuccessStage -eq 'OPERATOR_OUTPUT_CONTRACT') { 'PASS' } else { 'FAIL_OR_SKIPPED' }
    $steps = @(
        [ordered]@{ name = [string]'INPUT_VALIDATION'; status = [string]$inputValidationStatusText },
        [ordered]@{ name = [string]'DECISION_BUILD'; status = [string]$decisionBuildStatusText },
        [ordered]@{ name = [string]'OPERATOR_OUTPUT_CONTRACT'; status = [string]$operatorContractStatusText }
    )
    $visualCoverageNode = Convert-ToHashtableSafe -Value (Safe-Get -Object $AuditResult -Key 'visual_coverage' -Default @{})
    $visualAuditActiveFlag = [bool](Safe-Get -Object $visualCoverageNode -Key 'visual_audit_active' -Default $false)
    $visualArtifactsStatus = if ($visualAuditActiveFlag) { 'PASS' } else { 'FAIL' }
    $visualScreenshotsPackaged = [int](Safe-Get -Object $visualCoverageNode -Key 'screenshots_packaged' -Default 0)
    $visualRoutesWithEvidence = [int](Safe-Get -Object $visualCoverageNode -Key 'routes_with_evidence' -Default 0)
    $messageText = if ([string]::IsNullOrWhiteSpace($errorMessage)) { $executiveSummary } else { $errorMessage }

    $runStatusMap = [ordered]@{
        run_id = [string]$runId
        target = [string]$targetValue
        mode = [string]$ResolvedMode
        started_at = [string]$runStartedAt
        finished_at = [string]$RunFinishedAt
        final_status = [string]$FinalStatus
        final_stage = [string]$CurrentStage
        last_success_stage = [string]$LastSuccessStage
    }
    $visualArtifactsMap = [ordered]@{
        visual_audit_active = [bool]$visualAuditActiveFlag
        screenshots_packaged = [int]$visualScreenshotsPackaged
        routes_with_evidence = [int]$visualRoutesWithEvidence
        status = [string]$visualArtifactsStatus
    }
    $artifactManifestSummaryMap = [ordered]@{
        artifacts = $artifactItemsSafe
        primary_truth_sources = $primaryTruthSafe
    }
    $evidenceMap = [ordered]@{
        source_status = [string]$sourceStatus
        live_status = [string]$liveStatus
        page_quality_status = [string]$pageQualityStatus
        product_status = [string]$productStatus
        product_reason = [string]$productReason
        product_actions = @($productActions)
        repo_summary_status = [string]$repoSummaryOut
        failure_stage = [string]$failedStage
        error_message = [string]$errorMessage
        error_class = [string]$errorClassText
        failure_node = [string]$failedStage
        decision_build_failed_node = [string]$decisionBuildFailedNode
        blocker = [string](Safe-Get -Object $Decision -Key 'core_problem' -Default '')
    }

    $contract = [ordered]@{
        schema_version = '2.0'
        run_id = [string]$runId
        started_at = [string]$runStartedAt
        finished_at = [string]$RunFinishedAt
        target_type = [string]$ResolvedMode
        steps = @($steps)
        final_status = [string]$FinalStatus
        failed_step = [string]$failedStage
        error_class = [string]$errorClassText
        message = [string]$messageText
        run_status = $runStatusMap
        executive_summary = [string]$executiveSummary
        key_evidence_excerpts = $evidenceMap
        visual_artifacts = $visualArtifactsMap
        repair_hint = $repairHint
        artifact_manifest_summary = $artifactManifestSummaryMap
        next_technical_move = [string]$nextMove
    }

    $manifestPath = Join-Path $reportsDir 'ARTIFACT_MANIFEST.json'
    Write-JsonFile -Path $manifestPath -Data ([ordered]@{
        run_id = $runId
        generated_at = $RunFinishedAt
        final_status = $FinalStatus
        artifacts = $artifactItemsSafe
    })

    $runReportJsonPath = Join-Path $reportsDir 'RUN_REPORT.json'
    Write-JsonFile -Path $runReportJsonPath -Data $contract

    $summaryPayload = [ordered]@{
        run_id = $runId
        mode = $ResolvedMode
        final_status = $FinalStatus
        final_stage = $CurrentStage
        last_success_stage = $LastSuccessStage
        failed_stage = $failedStage
        error_message = $errorMessage
        error_class = $errorClassText
        decision_build_failed_node = $decisionBuildFailedNode
        confirmed_passing_stages = $confirmedPassingStagesSafe
        usable_partial_artifacts_exist = [bool]$usablePartialArtifacts
        next_technical_move = $nextMove
        key_evidence_excerpts = $evidenceMap
        primary_truth_sources = $primaryTruthSafe
    }

    if ($FinalStatus -in @('FAIL', 'PARTIAL')) {
        Write-JsonFile -Path (Join-Path $reportsDir 'FAILURE_SUMMARY.json') -Data $summaryPayload
    }
    else {
        Write-JsonFile -Path (Join-Path $reportsDir 'SUCCESS_SUMMARY.json') -Data $summaryPayload
    }

    $lines = @(
        'RUN STATUS',
        "- run_id: $($contract.run_status.run_id)",
        "- target: $($contract.run_status.target)",
        "- mode: $($contract.run_status.mode)",
        "- started_at: $($contract.run_status.started_at)",
        "- finished_at: $($contract.run_status.finished_at)",
        "- final_status: $($contract.run_status.final_status)",
        "- final_stage: $($contract.run_status.final_stage)",
        "- last_success_stage: $($contract.run_status.last_success_stage)",
        '',
        'EXECUTIVE SUMMARY',
        $executiveSummary,
        '',
        'KEY EVIDENCE EXCERPTS',
        "- source_status: $($evidenceMap.source_status)",
        "- live_status: $($evidenceMap.live_status)",
        "- page_quality_status: $($evidenceMap.page_quality_status)",
        "- product_status: $($evidenceMap.product_status)",
        "- product_reason: $($evidenceMap.product_reason)",
        "- repo_summary_status: $($evidenceMap.repo_summary_status)",
        "- failure_stage: $($evidenceMap.failure_stage)",
        "- failure_node: $($evidenceMap.failure_node)",
        "- decision_build_failed_node: $($evidenceMap.decision_build_failed_node)",
        "- blocker: $($evidenceMap.blocker)",
        "- error_message: $($evidenceMap.error_message)",
        "- error_class: $($evidenceMap.error_class)",
        '',
        'REPAIR HINT',
        "- target_file: $([string](Safe-Get -Object $repairHint -Key 'target_file' -Default 'agents/gh_batch/site_auditor_cloud/agent.ps1'))",
        "- broken_block: $([string](Safe-Get -Object $repairHint -Key 'broken_block' -Default 'UNKNOWN'))",
        "- next_action: $([string](Safe-Get -Object $repairHint -Key 'next_action' -Default $nextMove))",
        "- priority_routes: $((@(Safe-Get -Object $repairHint -Key 'priority_routes' -Default @()) -join ', '))",
        '',
        'ARTIFACT MANIFEST SUMMARY'
    )

    foreach ($artifact in ($artifactItemsSafe | Sort-Object -Property @{Expression='priority_for_operator';Descending=$false}, @{Expression='path';Descending=$false})) {
        $lines += "- $($artifact.path) | type=$($artifact.artifact_type) | priority=$($artifact.priority_for_operator) | purpose=$($artifact.purpose)"
    }

    $lines += ''
    $lines += 'PRIMARY TRUTH SOURCES'
    foreach ($truth in $primaryTruthSafe) {
        $lines += "- $truth"
    }

    if ($FinalStatus -in @('FAIL', 'PARTIAL')) {
        $lines += ''
        $lines += 'FAILURE SUMMARY'
        $lines += "- exact_failed_stage_or_node: $failedStage"
        $lines += "- error_class: $($evidenceMap.error_class)"
        $lines += "- error_message: $($evidenceMap.error_message)"
        $lines += "- confirmed_passing_stages: $(($confirmedPassingStagesSafe -join ', '))"
        $lines += "- usable_partial_artifacts_exist: $usablePartialArtifacts"
    }

    $lines += ''
    $lines += 'NEXT TECHNICAL MOVE'
    $lines += $nextMove

    Write-TextFile -Path (Join-Path $reportsDir 'RUN_REPORT.txt') -Lines $lines

    $reportFiles.Add('reports/ARTIFACT_MANIFEST.json')
    $reportFiles.Add('reports/RUN_REPORT.json')
    $reportFiles.Add('reports/RUN_REPORT.txt')
    if ($FinalStatus -in @('FAIL', 'PARTIAL')) {
        $reportFiles.Add('reports/FAILURE_SUMMARY.json')
    }
    else {
        $reportFiles.Add('reports/SUCCESS_SUMMARY.json')
    }
}

function Write-OperatorOutputs {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [hashtable]$AuditResult,
        [hashtable]$Decision,
        [string]$CurrentStage = '',
        [string]$LastSuccessStage = '',
        [string]$RunFinishedAt = '',
        [string]$FailureReason = ''
    )

    $AuditResult = Normalize-AuditResult -AuditResult $AuditResult

    $remediationPackage = Safe-Get -Object $Decision -Key 'remediation_package' -Default @{}
    $productCloseout = Normalize-ProductCloseoutForOutput -Value (Safe-Get -Object $Decision -Key 'product_closeout' -Default $null)
    $productStatusDetail = Convert-ToProductStatus -Decision $Decision -FinalStatus $FinalStatus
    $productStatusText = Get-ProductStatusString -ProductStatus $productStatusDetail -Default 'FAIL'
    if ($productStatusText -notin @('SUCCESS', 'NEEDS_FIX', 'FAIL')) { $productStatusText = 'FAIL' }
    $productActions = Convert-ToStringArraySafe -Value (Safe-Get -Object $Decision -Key 'do_next' -Default @())
    if (-not $productActions -or @($productActions).Count -eq 0) {
        $productActions = @(
            'Fix critical UI contamination issues',
            'Add decision clarity to entry pages',
            'Establish clear action paths for user'
        )
    }

    $AuditResult['product_status'] = [string]$productStatusText
    $AuditResult['product_status_detail'] = $productStatusDetail
    $AuditResult['product_actions'] = @($productActions)
    $AuditResult['product_closeout'] = $productCloseout
    $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'summary' -Default @{})
    $routeDetailsForCoverage = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'route_details' -Default @())
    $visualCoverage = Convert-ToHashtableSafe -Value (Safe-Get -Object $liveSummary -Key 'visual_coverage' -Default @{})
    $visualCoverageKeys = @($visualCoverage.Keys)
    if ($visualCoverageKeys.Count -eq 0) {
        $routeDetailsForCoverageSafe = @($routeDetailsForCoverage)
        $routesTotalLocal = [int]$routeDetailsForCoverageSafe.Count
        $capturedRouteCandidates = @($routeDetailsForCoverageSafe | Where-Object { [int](Safe-Get -Object $_ -Key 'screenshotCount' -Default 0) -ge 3 })
        $routesCapturedLocal = [int]$capturedRouteCandidates.Count
        $coverageScoreLocal = if ($routesTotalLocal -gt 0) { [int][Math]::Round((($routesCapturedLocal / [double]$routesTotalLocal) * 100), 0) } else { 0 }
        $visualCoverage = [ordered]@{
            routes_total = [int]$routesTotalLocal
            routes_captured = [int]$routesCapturedLocal
            issue_screenshots = [int](Safe-Get -Object $liveSummary -Key 'issue_screenshots' -Default 0)
            coverage_score = [int]$coverageScoreLocal
        }
    }
    $decisionStage = [string](Safe-Get -Object $Decision -Key 'stage' -Default 'BROKEN')
    $decisionCore = [string](Safe-Get -Object $Decision -Key 'core_problem' -Default 'Decision core problem was not generated.')
    $decisionP0 = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'p0' -Default @())
    $doNextNow = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next_now' -Default (Safe-Get -Object $Decision -Key 'do_next' -Default @()))
    $doNextAfter = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next_after' -Default @())
    $validatorPass = ($FinalStatus -ne 'FAIL')
    $targetText = if ([string]::IsNullOrWhiteSpace([string]$env:TARGET_REPO_PATH)) { [string]$env:BASE_URL } else { [string]$env:TARGET_REPO_PATH }
    $decisionCoreText = (($decisionCore -replace "`r", ' ') -replace "`n", ' ').Trim()
    $decisionP0Safe = @($decisionP0 | Select-Object -Unique)
    $doNextNowSafe = @($doNextNow | Select-Object -Unique)
    $doNextAfterSafe = @($doNextAfter | Select-Object -Unique)
    $AuditResult['schema_version'] = [string]'4.0'
    $AuditResult['run_id'] = [string]$runId
    $AuditResult['target'] = [string]$targetText
    $AuditResult['runtime'] = [ordered]@{
        status = [string]$FinalStatus
        validator_pass = [bool]$validatorPass
        final_output_contract_pass = [bool]$false
        diagnostic_or_result_present = [bool]$false
    }
    $decisionRepairHint = Convert-ToHashtableSafe -Value (Safe-Get -Object $Decision -Key 'repair_hint' -Default @{})
    $decisionPriorityRoutes = Convert-ToStringArraySafe -Value (Safe-Get -Object $Decision -Key 'priority_routes' -Default @())
    $decisionPriorityRoutesSafe = @($decisionPriorityRoutes)
    $AuditResult['decision'] = [ordered]@{
        stage = [string]$decisionStage
        core_problem = [string]$decisionCoreText
        p0 = @($decisionP0Safe)
        do_next = [ordered]@{
            now = @($doNextNowSafe)
            after = @($doNextAfterSafe)
        }
        repair_hint = $decisionRepairHint
        priority_routes = @($decisionPriorityRoutesSafe)
    }
    $routeDetailsForVisualTruth = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'route_details' -Default @())
    $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
    $packagedScreenshotDir = Join-Path $reportsDir 'screenshots'
    $legacyScreenshotDir = Join-Path $base 'screenshots'
    $capturedScreenshotCount = 0
    if (Test-Path -Path $packagedScreenshotDir -PathType Container) {
        $packagedScreenshotsSafe = @(Get-ChildItem -Path $packagedScreenshotDir -Include *.png,*.jpg,*.jpeg,*.webp -File -Recurse -ErrorAction SilentlyContinue)
        $capturedScreenshotCount += $packagedScreenshotsSafe.Count
    }
    if (Test-Path -Path $legacyScreenshotDir -PathType Container) {
        $legacyScreenshotsSafe = @(Get-ChildItem -Path $legacyScreenshotDir -Include *.png,*.jpg,*.jpeg,*.webp -File -Recurse -ErrorAction SilentlyContinue)
        $capturedScreenshotCount += $legacyScreenshotsSafe.Count
    }

    $routesWithEvidence = 0
    foreach ($routeItem in @($routeDetailsForVisualTruth)) {
        $routeNode = Convert-ToHashtableSafe -Value $routeItem
        $routeScreenshotCount = [int](Safe-Get -Object $routeNode -Key 'screenshotCount' -Default 0)
        if ($routeScreenshotCount -le 0) {
            $routeScreenshotsSafe = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $routeNode -Key 'screenshots' -Default @()))
            $routeIssueScreenshotsSafe = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $routeNode -Key 'issue_screenshots' -Default @()))
            $routeScreenshotCount = $routeScreenshotsSafe.Count
            $routeScreenshotCount += $routeIssueScreenshotsSafe.Count
        }
        if ($routeScreenshotCount -gt 0) {
            $routesWithEvidence++
            $capturedScreenshotCount += $routeScreenshotCount
        }
    }

    $capturedScreenshotCount = [int][Math]::Max(0, $capturedScreenshotCount)
    $visualAuditActive = ((Test-Path -Path $visualManifestPath -PathType Leaf) -or ($capturedScreenshotCount -gt 0) -or ($routesWithEvidence -gt 0))
    $visualCoverage['visual_audit_active'] = [bool]$visualAuditActive
    $visualCoverage['screenshots_packaged'] = [int]$capturedScreenshotCount
    $visualCoverage['routes_with_evidence'] = [int]$routesWithEvidence
    $AuditResult['visual_coverage'] = $visualCoverage
    $AuditResult['facts'] = [ordered]@{
        mode = [string]$ResolvedMode
        required_inputs = Normalize-CollectionShape -Value (Safe-Get -Object $AuditResult -Key 'required_inputs' -Default @())
        total_routes = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
        empty_routes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
        thin_routes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
        contaminated_routes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    }
    $AuditResult['artifacts'] = [ordered]@{
        reports = @('reports/audit_result.json', 'reports/RUN_REPORT.json')
        outbox = @('outbox/11A_EXECUTIVE_SUMMARY.txt', 'outbox/00_PRIORITY_ACTIONS.txt', 'outbox/01_TOP_ISSUES.txt')
        screenshots_dir = 'screenshots'
    }

    $liveLayer = Safe-Get -Object $AuditResult -Key 'live' -Default @{}
    $liveSummary = Safe-Get -Object $liveLayer -Key 'summary' -Default @{}
    $liveEnabled = [bool](Safe-Get -Object $liveLayer -Key 'enabled' -Default $false)
    $liveOk = [bool](Safe-Get -Object $liveLayer -Key 'ok' -Default $false)
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    if ($liveEnabled -and $liveOk -and ($pageQualityStatus -in @('NOT_EVALUATED', 'PARTIAL'))) {
        $liveLayer.ok = $false
        $liveWarnings = Convert-ToStringArraySafe -Value (Safe-Get -Object $liveLayer -Key 'warnings' -Default @())
        $degradedWarning = "OUTPUT_CONSISTENCY: live.ok forced false because page_quality_status=$pageQualityStatus."
        if (-not (@($liveWarnings) -contains $degradedWarning)) {
            $liveWarnings = @($liveWarnings + $degradedWarning)
        }
        $liveLayer.warnings = $liveWarnings
        $AuditResult['live'] = $liveLayer
    }

    if ($AuditResult['decision'] -is [System.Collections.IDictionary]) {
        $AuditResult['decision']['product_closeout'] = $productCloseout
    }

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    Write-JsonFile -Path $auditResultPath -Data $AuditResult
    $reportFiles.Add('reports/audit_result.json')

    $packageName = [string](Safe-Get -Object $remediationPackage -Key 'package_name' -Default 'MIXED_RECOVERY_PACKAGE')
    $packageGoal = [string](Safe-Get -Object $remediationPackage -Key 'package_goal' -Default 'Stabilize highest-impact route-quality cluster first.')
    $packageTargets = Convert-ToObjectArraySafe -Value (Safe-Get -Object $remediationPackage -Key 'primary_targets' -Default @())
    $packageSteps = Convert-ToObjectArrayOrEmpty -Value @((Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next' -Default @())) | Select-Object -First 5)
    $remediationPayload = @{
        package_name = $packageName
        goal = $packageGoal
        execution_mode = 'linear'
        primary_targets = @($packageTargets | Select-Object -First 5)
        why_first = [string](Safe-Get -Object $remediationPackage -Key 'why_first' -Default 'Prioritize the highest-impact repeated blocker first.')
        steps = @($packageSteps)
        expected_impact = [string](Safe-Get -Object $remediationPackage -Key 'expected_impact' -Default 'Single-path remediation should reduce primary blocker recurrence and improve route conversion readiness.')
        success_check = [string](Safe-Get -Object $remediationPackage -Key 'success_check' -Default 'Rerun SITE_AUDITOR and verify blocker counts decrease on targeted routes.')
    }
    $remediationPath = Join-Path $reportsDir 'REMEDIATION_PACKAGE.json'
    Write-JsonFile -Path $remediationPath -Data $remediationPayload
    $reportFiles.Add('reports/REMEDIATION_PACKAGE.json')

    $decisionP0 = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'p0' -Default @())
    $decisionP1 = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'p1' -Default @())
    $decisionP2 = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'p2' -Default @())
    $decisionProblems = Normalize-ToArray (Safe-Get -Object $Decision -Key 'problems' -Default @($decisionP0 + $decisionP1))
    $topIssues = @($decisionProblems)
    if (-not [string]::IsNullOrWhiteSpace($packageGoal)) {
        $topIssues = @("Primary remediation package: $packageName — $packageGoal") + @($topIssues)
    }
    $topIssuesSafe = @(Normalize-ToArray $topIssues)
    if ($topIssuesSafe.Count -eq 0) {
        $topIssues = @($decisionP2)
        $topIssuesSafe = @(Normalize-ToArray $topIssues)
    }
    if ($topIssuesSafe.Count -eq 0 -and $FinalStatus -eq 'FAIL') {
        $topIssues = @($decisionP0)
        $topIssuesSafe = @(Normalize-ToArray $topIssues)
    }
    if ($topIssuesSafe.Count -eq 0) {
        $topIssues = @('No major issues detected from collected source/live evidence.')
    }

    $priorityActions = New-Object System.Collections.Generic.List[string]
    $doNextItems = @(
        Convert-ToObjectArrayOrEmpty -Value (
            @(
                Convert-ToObjectArrayOrEmpty -Value (
                    Safe-Get -Object $Decision -Key 'next_actions' -Default (
                        Safe-Get -Object $Decision -Key 'do_next' -Default @()
                    )
                )
            ) | Select-Object -First 3
        )
    )

    $doNextItemsSafe = @($doNextItems)
    if ($doNextItemsSafe.Count -gt 0) {
        for ($i = 0; $i -lt $doNextItemsSafe.Count; $i++) {
            $priorityActions.Add("$($i + 1)) $($doNextItemsSafe[$i])")
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
        mode = [string]$ResolvedMode
        status = [string]$FinalStatus
        generated_from = 'audit_result.json'
        core_problem = [string]$Decision.core_problem
        top_issues = @($topIssues)
        priority_actions = @($priorityActions)
        repair_hint = $decisionRepairHint
    }
    $howToFixPath = Join-Path $reportsDir 'HOW_TO_FIX.json'
    Write-JsonFile -Path $howToFixPath -Data $howToFix
    $reportFiles.Add('reports/HOW_TO_FIX.json')

    $priorityPath = Join-Path $outboxDir '00_PRIORITY_ACTIONS.txt'
    Write-TextFile -Path $priorityPath -Lines $priorityActions
    $reportFiles.Add('outbox/00_PRIORITY_ACTIONS.txt')

    $issuesPath = Join-Path $outboxDir '01_TOP_ISSUES.txt'
    Write-TextFile -Path $issuesPath -Lines $topIssues
    $reportFiles.Add('outbox/01_TOP_ISSUES.txt')

    $sourceStatus = if (-not (Safe-Get -Object $AuditResult['source'] -Key 'enabled' -Default $false)) { 'OFF' } elseif (Safe-Get -Object $AuditResult['source'] -Key 'ok' -Default $false) { 'PASS' } else { 'FAIL' }
    $liveStatus = if (-not (Safe-Get -Object $AuditResult['live'] -Key 'enabled' -Default $false)) { 'OFF' } elseif (Safe-Get -Object $AuditResult['live'] -Key 'ok' -Default $false) { 'PASS' } else { 'FAIL' }
    $requiredInputs = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $AuditResult -Key 'required_inputs' -Default @())
    $requiredInputsSafe = @($requiredInputs)
    $requiredInputsLine = if ($requiredInputsSafe.Count -gt 0) { $requiredInputsSafe -join ', ' } else { 'Not required for this mode.' }
    $repoRoot = Safe-Get -Object $AuditResult['source'] -Key 'root' -Default $null
    $sourceEnabled = [bool](Safe-Get -Object $AuditResult['source'] -Key 'enabled' -Default $false)

    $summaryLines = @(
        "STAGE: $decisionStage",
        '',
        'CORE PROBLEM:',
        $decisionCore,
        '',
        'P0:',
        $((@($decisionP0) -join "`n")),
        '',
        'DO NOW:',
        $((@($doNextNow) -join "`n")),
        '',
        'DO AFTER:',
        $((@($doNextAfter) -join "`n"))
    )
    $summaryPath = Join-Path $outboxDir '11A_EXECUTIVE_SUMMARY.txt'
    Write-TextFile -Path $summaryPath -Lines $summaryLines
    $reportFiles.Add('outbox/11A_EXECUTIVE_SUMMARY.txt')

    $metaBriefPath = Join-Path $reportsDir '12A_META_AUDIT_BRIEF.txt'
    $metaBriefLines = Build-MetaAuditBriefLines -AuditResult $AuditResult -Decision $Decision -FinalStatus $FinalStatus
    Write-TextFile -Path $metaBriefPath -Lines $metaBriefLines
    $reportFiles.Add('reports/12A_META_AUDIT_BRIEF.txt')

    $siteDiagnosis = Safe-Get -Object $Decision -Key 'site_diagnosis' -Default @{}
    $maturity = Safe-Get -Object $Decision -Key 'maturity_readiness' -Default @{}
    $maturityClass = [string](Safe-Get -Object $maturity -Key 'class' -Default 'NOT_READY')
    $siteStage = 1
    if ($maturityClass -in @('READY_SCALE', 'READY_GROWTH')) { $siteStage = 4 }
    elseif ($maturityClass -eq 'READY_BASELINE') { $siteStage = 3 }
    elseif ($maturityClass -in @('PARTIAL_READY', 'NEEDS_FOUNDATION')) { $siteStage = 2 }

    $primaryProblem = [string](Safe-Get -Object $Decision -Key 'core_problem' -Default 'Core problem was not generated; use remediation package as the immediate operator path.')
    if ([string]::IsNullOrWhiteSpace($primaryProblem)) {
        $primaryProblem = 'Core problem was not generated; use remediation package as the immediate operator path.'
    }
    $criticalBlockers = @(
        Convert-ToObjectArrayOrEmpty -Value (
            @($decisionP0 | Select-Object -First 3)
        )
    )
    $criticalBlockersSafe = @($criticalBlockers)
    if ($criticalBlockersSafe.Count -eq 0) {
        $criticalBlockers = @('No critical blockers identified.')
        $criticalBlockersSafe = @($criticalBlockers)
    }
    $doNextItems = @(
        Convert-ToObjectArrayOrEmpty -Value (
            @(
                Convert-ToObjectArrayOrEmpty -Value (
                    Safe-Get -Object $Decision -Key 'do_next' -Default @()
                )
            ) | Select-Object -First 3
        )
    )

    $doNextItemsReportSafe = @($doNextItems)
    if ($doNextItemsReportSafe.Count -eq 0) {
        $doNextItems = @('Execute remediation package steps from reports/REMEDIATION_PACKAGE.json and rerun SITE_AUDITOR.')
        $doNextItemsReportSafe = @($doNextItems)
    }
    $successSignalItems = @(
        'Primary target page is updated in source/live evidence. (YES/NO)',
        'A clear CTA exists on each primary target route. (YES/NO)',
        'Primary target content is expanded beyond thin-state threshold. (YES/NO)',
        'Internal supporting links exist on each primary target route. (YES/NO)'
    )

    $reportLines = @(
        "MODE: $ResolvedMode",
        "OVERALL STATUS: $FinalStatus",
        "SOURCE AUDIT: $sourceStatus",
        "LIVE AUDIT: $liveStatus",
        "REQUIRED INPUTS: $requiredInputsLine",
        'SECTION: PRIMARY PROBLEM',
        $primaryProblem,
        '',
        'SECTION: CRITICAL BLOCKERS'
    )
    for ($i = 0; $i -lt $criticalBlockersSafe.Count; $i++) {
        $item = $criticalBlockersSafe[$i]
        $reportLines += "- WHAT: $item"
        $reportLines += "- ORDER: $($i + 1)"
        $reportLines += '- WHY: This condition blocks reliable operator execution or baseline quality.'
        $reportLines += '- IMPACT: Shipping without this fix risks false confidence and repeat audit failures.'
    }
    $reportLines += ''
    $reportLines += 'SECTION: OPERATOR PATH'
    for ($i = 0; $i -lt $doNextItemsReportSafe.Count; $i++) {
        $reportLines += "STEP $($i + 1) -> $($doNextItemsReportSafe[$i])"
    }
    $reportLines += ''
    $reportLines += 'SECTION: SUCCESS SIGNAL'
    foreach ($signal in $successSignalItems) {
        $reportLines += "- $signal"
    }
    $reportLines += ''
    $reportLines += 'SECTION: SITE STAGE'
    $reportLines += "STAGE $siteStage"
    $reportLines += "DIAGNOSIS: $([string](Safe-Get -Object $siteDiagnosis -Key 'class' -Default 'INCONCLUSIVE_DIAGNOSIS'))"
    $reportLines += "MATURITY: $maturityClass"
    $reportLines += "PRODUCT STATUS: $productStatusText"
    $reportLines += "PRODUCT REASON: $([string](Safe-Get -Object $productStatusDetail -Key 'reason' -Default 'Closeout reason unavailable; review reports/audit_result.json.'))"
    $reportLines += "PRODUCT CONFIDENCE: $([string](Safe-Get -Object $productStatusDetail -Key 'confidence' -Default 'low'))"
    $reportLines += "PRIMARY REMEDIATION PACKAGE: $packageName"

    $reportFilesSafe = @($reportFiles)
    $manifest = @{
        mode = [string]$ResolvedMode
        status = [string]$FinalStatus
        repo_root = [string]$repoRoot
        target_repo_bound = [bool]$sourceEnabled
        output_root = [string]$base
        report_files = @($reportFilesSafe)
        run_id = [string]$runId
        started_at = [string]$runStartedAt
        finished_at = [string]$RunFinishedAt
        final_stage = [string]$CurrentStage
        last_success_stage = [string]$LastSuccessStage
        timestamp = [string]$timestamp
    }

    $manifestPath = Join-Path $reportsDir 'run_manifest.json'
    Write-JsonFile -Path $manifestPath -Data $manifest
    $reportFiles.Add('reports/run_manifest.json')
    $reportLines += 'MANIFEST: reports/run_manifest.json'

    $reportPath = Join-Path $outboxDir 'REPORT.txt'
    Write-TextFile -Path $reportPath -Lines $reportLines
    Write-Host "DEBUG REPORT PATH: $reportPath"
    Test-Path $reportPath | ForEach-Object {
        Write-Host "DEBUG REPORT EXISTS: $_"
    }

    Write-RunForensicsReports -ResolvedMode $ResolvedMode -FinalStatus $FinalStatus -AuditResult $AuditResult -Decision $Decision -FailureReason $FailureReason -CurrentStage $CurrentStage -LastSuccessStage $LastSuccessStage -RunFinishedAt $RunFinishedAt
}

function Ensure-OutputContract {
    param(
        [string]$ResolvedMode,
        [string]$FinalStatus,
        [string]$FailureReason
    )

    Ensure-Dir $outboxDir
    Ensure-Dir $reportsDir
    $isDecisionBuildFailure = (($FinalStatus -in @('FAIL', 'PARTIAL')) -and ([string]$currentStage -eq 'DECISION_BUILD'))

    $auditResultPath = Join-Path $reportsDir 'audit_result.json'
    if (-not (Test-Path $auditResultPath -PathType Leaf)) {
        $fallbackAuditResult = @{
            status = $FinalStatus
            timestamp = (Get-Date).ToString('o')
            mode = $ResolvedMode
            error = if ([string]::IsNullOrWhiteSpace($FailureReason)) { 'FAILED: no report generated' } else { $FailureReason }
            product_status = 'NEEDS_FIX'
            product_status_detail = [ordered]@{
                status = 'NEEDS_FIX'
                reason = 'Fallback audit result generated without full decision context.'
                confidence = 'low'
                run_status = $FinalStatus
            }
            product_closeout = [ordered]@{
                class = 'BLOCKED_BY_MISSING_OPERATOR_OUTPUT_CONTRACT'
                reason = 'Fallback audit result generated without full decision context.'
                confidence = 'low'
                checks = @()
                evidence = @("final_status=$FinalStatus", 'fallback_contract=true')
            }
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
    $reportMirrorPath = Join-Path $reportsDir 'REPORT.txt'
    if (Test-Path $reportPath -PathType Leaf) {
        Copy-Item -Path $reportPath -Destination $reportMirrorPath -Force -ErrorAction SilentlyContinue
    }


    $runReportJsonPath = Join-Path $reportsDir 'RUN_REPORT.json'
    $auditResultNode = @{}
    if (Test-Path $auditResultPath -PathType Leaf) {
        try {
            $parsedAuditResultNode = Get-Content -Path $auditResultPath -Raw | ConvertFrom-Json -Depth 64 -AsHashtable
            if ($parsedAuditResultNode -is [System.Collections.IDictionary]) {
                $auditResultNode = $parsedAuditResultNode
            }
        }
        catch {
            $auditResultNode = @{}
        }
    }

    if (-not (Test-Path $runReportJsonPath -PathType Leaf)) {
        $fallbackTruth = Get-FallbackTruthEvidence -AuditResultPath $auditResultPath -FailureReason $FailureReason -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage
        $fallbackErrorClass = [string](Safe-Get -Object $fallbackTruth -Key 'error_class' -Default '')
        $fallbackNextMove = if ($FinalStatus -eq 'PASS') {
            'No technical repair node remains.'
        }
        else {
            "Inspect failed node '$($fallbackTruth.failure_stage)' and remediate the blocker before rerun."
        }
        $primaryTruthSources = Convert-ToObjectArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'primary_truth_sources' -Default @())
        if (@($primaryTruthSources).Count -le 0) {
            $primaryTruthSources = @('reports/audit_result.json')
        }
        $repairHint = [ordered]@{
            target_file = 'agents/gh_batch/site_auditor_cloud/agent.ps1'
            broken_block = [string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage)
            reason = [string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.')
            next_action = $fallbackNextMove
            priority_routes = @()
        }

        $visualCoverageNode = Safe-Get -Object $auditResultNode -Key 'visual_coverage' -Default @{}
        if (-not ($visualCoverageNode -is [System.Collections.IDictionary])) {
            $visualCoverageNode = @{}
        }

        $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
        $visualAuditActive = [bool](Safe-Get -Object $visualCoverageNode -Key 'visual_audit_active' -Default $false)
        if ((-not $visualAuditActive) -and (Test-Path $visualManifestPath -PathType Leaf)) {
            try {
                $manifestRaw = Get-Content -Path $visualManifestPath -Raw
                $manifestData = $manifestRaw | ConvertFrom-Json -Depth 64
                $manifestItems = Convert-ToObjectArraySafe -Value $manifestData
                if (@($manifestItems).Count -gt 0) {
                    $manifestRouteCount = @($manifestItems).Count
                    $manifestScreenshotCount = 0
                    foreach ($manifestItem in @($manifestItems)) {
                        $manifestScreenshotCount += [int](Safe-Get -Object $manifestItem -Key 'screenshotCount' -Default 0)
                    }
                    $visualCoverageNode = [ordered]@{
                        visual_audit_active = $true
                        screenshots_packaged = [int]$manifestScreenshotCount
                        routes_with_evidence = [int]$manifestRouteCount
                    }
                }
            }
            catch {
                Write-Host "VISUAL_MANIFEST_FALLBACK_PARSE_FAIL: $($_.Exception.Message)"
            }
        }

        $fallbackContract = [ordered]@{
            run_status = [ordered]@{
                run_id = $runId
                target = if ([string]::IsNullOrWhiteSpace([string]$env:TARGET_REPO_PATH)) { [string]$env:BASE_URL } else { [string]$env:TARGET_REPO_PATH }
                mode = $ResolvedMode
                started_at = $runStartedAt
                finished_at = $runFinishedAt
                final_status = $FinalStatus
                final_stage = $currentStage
                last_success_stage = $lastSuccessStage
            }
            executive_summary = 'Fallback run report generated because primary operator report contract was missing.'
            error_class = [string]$fallbackErrorClass
            key_evidence_excerpts = [ordered]@{
                source_status = [string](Safe-Get -Object $fallbackTruth -Key 'source_status' -Default 'UNKNOWN')
                live_status = [string](Safe-Get -Object $fallbackTruth -Key 'live_status' -Default 'UNKNOWN')
                page_quality_status = [string](Safe-Get -Object $fallbackTruth -Key 'page_quality_status' -Default 'NOT_EVALUATED')
                product_status = [string](Safe-Get -Object $fallbackTruth -Key 'product_status' -Default 'UNKNOWN')
                product_reason = [string](Safe-Get -Object $fallbackTruth -Key 'product_reason' -Default 'Fallback report only.')
                product_actions = @(Convert-ToStringArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'product_actions' -Default @()))
                repo_summary_status = [string](Safe-Get -Object $fallbackTruth -Key 'repo_summary_status' -Default 'UNKNOWN')
                failure_stage = [string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage)
                error_message = [string](Safe-Get -Object $fallbackTruth -Key 'error_message' -Default '')
                error_class = [string]$fallbackErrorClass
                failure_node = [string](Safe-Get -Object $fallbackTruth -Key 'failure_node' -Default $currentStage)
                blocker = [string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.')
            }
            visual_artifacts = [ordered]@{
                visual_audit_active = [bool](Safe-Get -Object $visualCoverageNode -Key 'visual_audit_active' -Default $false)
                screenshots_packaged = [int](Safe-Get -Object $visualCoverageNode -Key 'screenshots_packaged' -Default 0)
                routes_with_evidence = [int](Safe-Get -Object $visualCoverageNode -Key 'routes_with_evidence' -Default 0)
                status = if ([bool](Safe-Get -Object $visualCoverageNode -Key 'visual_audit_active' -Default $false)) { 'PASS' } else { 'FAIL' }
            }
            repair_hint = $repairHint
            artifact_manifest_summary = [ordered]@{
                artifacts = @(
                    [ordered]@{ path = 'reports/audit_result.json'; artifact_type = 'truth_audit'; purpose = 'Primary structured source/live/decision truth.'; priority_for_operator = 'high' },
                    [ordered]@{ path = 'reports/RUN_REPORT.txt'; artifact_type = 'run_report_text'; purpose = 'Top-level operator-ready forensic report.'; priority_for_operator = 'high' },
                    [ordered]@{ path = 'reports/11A_EXECUTIVE_SUMMARY.txt'; artifact_type = 'summary'; purpose = 'Human executive summary.'; priority_for_operator = 'high' },
                    [ordered]@{ path = 'outbox/REPORT.txt'; artifact_type = 'operator_report'; purpose = 'Legacy operator summary output.'; priority_for_operator = 'medium' }
                )
                primary_truth_sources = @($primaryTruthSources)
            }
            next_technical_move = $fallbackNextMove
        }
        Write-JsonFile -Path $runReportJsonPath -Data $fallbackContract
        $fallbackWorkedStages = Convert-ToObjectArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'confirmed_passing_stages' -Default @())
        $workedBeforeFailure = if (@($fallbackWorkedStages).Count -gt 0) {
            @($fallbackWorkedStages) -join ', '
        }
        else {
            'No confirmed passing stages were recorded before failure.'
        }
        $fallbackDidNotComplete = if ($isDecisionBuildFailure) {
            'DECISION_BUILD materialization, operator output contract assembly, and downstream summary generation.'
        }
        else {
            "Stage '$([string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage))' and downstream operator output generation."
        }
        Write-TextFile -Path (Join-Path $reportsDir 'RUN_REPORT.txt') -Lines @(
            'RUN STATUS',
            "- run_id: $runId",
            "- mode: $ResolvedMode",
            "- final_status: $FinalStatus",
            "- final_stage: $currentStage",
            "- last_success_stage: $lastSuccessStage",
            '',
            'EXECUTIVE SUMMARY',
            'Fallback run report generated because primary operator report contract was missing.',
            '',
            'FAILSAFE OPERATOR REPORT',
            "- MODE: $ResolvedMode",
            "- FINAL STATUS: $FinalStatus",
            "- FINAL STAGE: $currentStage",
            "- LAST SUCCESS STAGE: $lastSuccessStage",
            "- EXACT BLOCKER: $([string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.'))",
            "- WHAT WORKED BEFORE FAILURE: $workedBeforeFailure",
            "- WHAT DID NOT COMPLETE: $fallbackDidNotComplete",
            "- ONE NEXT TECHNICAL MOVE: $fallbackNextMove",
            "- AVAILABLE TRUTH FILES: $((@($primaryTruthSources) -join ', '))",
            '',
            'NEXT TECHNICAL MOVE',
            $fallbackNextMove
        )
        Write-TextFile -Path (Join-Path $reportsDir '11A_EXECUTIVE_SUMMARY.txt') -Lines @(
            "MODE: $ResolvedMode",
            "FINAL STATUS: $FinalStatus",
            "FINAL STAGE: $currentStage",
            "LAST SUCCESS STAGE: $lastSuccessStage",
            "EXACT BLOCKER: $([string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.'))",
            "WHAT WORKED BEFORE FAILURE: $workedBeforeFailure",
            "WHAT DID NOT COMPLETE: $fallbackDidNotComplete",
            "ONE NEXT TECHNICAL MOVE: $fallbackNextMove",
            "AVAILABLE TRUTH FILES: $((@($primaryTruthSources) -join ', '))"
        )
        Write-JsonFile -Path (Join-Path $reportsDir 'ARTIFACT_MANIFEST.json') -Data ([ordered]@{
            run_id = $runId
            generated_at = $runFinishedAt
            final_status = $FinalStatus
            artifacts = @(
                [ordered]@{ path = 'reports/audit_result.json'; artifact_type = 'truth_audit'; purpose = 'Primary structured source/live/decision truth.'; priority_for_operator = 'high' },
                [ordered]@{ path = 'reports/RUN_REPORT.txt'; artifact_type = 'run_report_text'; purpose = 'Top-level operator-ready forensic report.'; priority_for_operator = 'high' },
                [ordered]@{ path = 'reports/11A_EXECUTIVE_SUMMARY.txt'; artifact_type = 'summary'; purpose = 'Human executive summary.'; priority_for_operator = 'high' },
                [ordered]@{ path = 'outbox/REPORT.txt'; artifact_type = 'operator_report'; purpose = 'Legacy operator summary output.'; priority_for_operator = 'medium' }
            )
        })
        $fallbackSummary = [ordered]@{
            run_id = $runId
            mode = $ResolvedMode
            final_status = $FinalStatus
            final_stage = $currentStage
            last_success_stage = $lastSuccessStage
            failed_stage = [string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage)
            error_message = [string](Safe-Get -Object $fallbackTruth -Key 'error_message' -Default '')
            error_class = [string]$fallbackErrorClass
            confirmed_passing_stages = @(Convert-ToObjectArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'confirmed_passing_stages' -Default @()))
            usable_partial_artifacts_exist = $true
            next_technical_move = $fallbackNextMove
            key_evidence_excerpts = $fallbackContract.key_evidence_excerpts
            primary_truth_sources = @($primaryTruthSources)
        }
        if ($FinalStatus -in @('FAIL', 'PARTIAL')) {
            Write-JsonFile -Path (Join-Path $reportsDir 'FAILURE_SUMMARY.json') -Data $fallbackSummary
        }
        else {
            Write-JsonFile -Path (Join-Path $reportsDir 'SUCCESS_SUMMARY.json') -Data $fallbackSummary
        }
    }

    if ($isDecisionBuildFailure) {
        $summaryPath = Join-Path $reportsDir '11A_EXECUTIVE_SUMMARY.txt'
        if (-not (Test-Path $summaryPath -PathType Leaf)) {
            $fallbackTruth = Get-FallbackTruthEvidence -AuditResultPath $auditResultPath -FailureReason $FailureReason -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage
            $fallbackNextMove = "Inspect failed node '$([string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage))' and remediate the blocker before rerun."
            $fallbackWorkedStages = Convert-ToObjectArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'confirmed_passing_stages' -Default @())
            $workedBeforeFailure = if (@($fallbackWorkedStages).Count -gt 0) { @($fallbackWorkedStages) -join ', ' } else { 'No confirmed passing stages were recorded before failure.' }
            $primaryTruthSources = Convert-ToObjectArraySafe -Value (Safe-Get -Object $fallbackTruth -Key 'primary_truth_sources' -Default @('reports/audit_result.json'))
            Write-TextFile -Path $summaryPath -Lines @(
                "MODE: $ResolvedMode",
                "FINAL STATUS: $FinalStatus",
                "FINAL STAGE: $currentStage",
                "LAST SUCCESS STAGE: $lastSuccessStage",
                "EXACT BLOCKER: $([string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.'))",
                "WHAT WORKED BEFORE FAILURE: $workedBeforeFailure",
                'WHAT DID NOT COMPLETE: DECISION_BUILD materialization, operator output contract assembly, and downstream summary generation.',
                "ONE NEXT TECHNICAL MOVE: $fallbackNextMove",
                "AVAILABLE TRUTH FILES: $((@($primaryTruthSources) -join ', '))"
            )
        }
    }

    $requiredArtifacts = New-Object System.Collections.Generic.List[string]
    $requiredArtifacts.Add((Join-Path $reportsDir 'audit_result.json'))
    $requiredArtifacts.Add((Join-Path $reportsDir 'RUN_REPORT.json'))
    $requiredArtifacts.Add((Join-Path $outboxDir '11A_EXECUTIVE_SUMMARY.txt'))
    $requiredArtifacts.Add((Join-Path $outboxDir '00_PRIORITY_ACTIONS.txt'))
    $requiredArtifacts.Add((Join-Path $outboxDir '01_TOP_ISSUES.txt'))
    $visualActive = -not [string]::IsNullOrWhiteSpace([string]$env:BASE_URL)
    if ($visualActive) {
        $requiredArtifacts.Add((Join-Path $reportsDir 'screenshots'))
    }

    $missingArtifacts = New-Object System.Collections.Generic.List[string]
    foreach ($artifactPath in @($requiredArtifacts)) {
        if (-not (Test-Path -Path $artifactPath)) {
            $missingArtifacts.Add($artifactPath)
        }
    }

    $auditResultNode = @{}
    if (Test-Path -Path $auditResultPath -PathType Leaf) {
        try { $auditResultNode = ConvertFrom-Json (Get-Content -Path $auditResultPath -Raw) -AsHashtable } catch { $auditResultNode = @{} }
    }
    if ($auditResultNode -isnot [System.Collections.IDictionary]) { $auditResultNode = @{} }
    $runtimeNode = Convert-ToHashtableSafe -Value (Safe-Get -Object $auditResultNode -Key 'runtime' -Default @{})
    $contractPass = ($missingArtifacts.Count -eq 0)
    $runtimeNode.final_output_contract_pass = [bool]$contractPass
    $runtimeNode.diagnostic_or_result_present = [bool]($contractPass -or (Test-Path -Path (Join-Path $reportsDir 'RUN_DIAGNOSTIC.txt') -PathType Leaf))
    if (-not $contractPass) { $runtimeNode.status = 'FAIL' }
    $auditResultNode.runtime = $runtimeNode
    if (-not $contractPass) {
        $auditResultNode.status = 'FAIL'
        $diagnostic = [ordered]@{
            failed_step = 'OUTPUT_CONTRACT_LOCK'
            succeeded_before_fail = $lastSuccessStage
            missing_or_broken_artifact = @($missingArtifacts)
            exact_next_repair_direction = 'Generate missing required artifacts before PASS/READY; rerun SITE_AUDITOR after fixing output contract boundary.'
        }
        Write-JsonFile -Path (Join-Path $reportsDir 'RUN_DIAGNOSTIC.json') -Data $diagnostic
        Write-TextFile -Path (Join-Path $reportsDir 'RUN_DIAGNOSTIC.txt') -Lines @(
            "failed_step: $($diagnostic.failed_step)",
            "succeeded_before_fail: $($diagnostic.succeeded_before_fail)",
            "missing_or_broken_artifact: $((@($diagnostic.missing_or_broken_artifact) -join ', '))",
            "exact_next_repair_direction: $($diagnostic.exact_next_repair_direction)"
        )
        $auditDecisionNode = Convert-ToHashtableSafe -Value (Safe-Get -Object $auditResultNode -Key 'decision' -Default @{})
        if (($auditDecisionNode -is [System.Collections.IDictionary]) -and [string](Safe-Get -Object $auditDecisionNode -Key 'stage' -Default '') -eq 'READY') {
            $auditDecisionNode['stage'] = 'BROKEN'
            $auditDecisionNode['core_problem'] = 'Final output contract is missing required artifacts; run is not READY.'
            $auditResultNode['decision'] = $auditDecisionNode
        }
        $script:status = 'FAIL'
        if ($null -eq $global:AuditError) {
            $global:AuditError = New-Object System.Exception("Output contract lock failed. Missing artifacts: $((@($missingArtifacts) -join ', '))")
        }
    }
    Write-JsonFile -Path $auditResultPath -Data $auditResultNode

    Write-SelfRepairArtifacts -ResolvedMode $ResolvedMode -FinalStatus $FinalStatus -FailureReason $FailureReason -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage

    $doneOk = Join-Path $outboxDir 'DONE.ok'
    $doneFail = Join-Path $outboxDir 'DONE.fail'
    if (Test-Path $doneOk) { Remove-Item $doneOk -Force }
    if (Test-Path $doneFail) { Remove-Item $doneFail -Force }

    if ($contractPass -and $FinalStatus -eq 'PASS' -and $null -eq $global:AuditError) {
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

    $currentStage = 'INPUT_VALIDATION'

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
            $sourceLayer = New-SourceLayer -Overrides (Invoke-SourceAuditZip -BasePath $base -InboxPath (Join-Path $base 'input/inbox') -ZipWorkRoot $zipWorkRoot)
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

    $warningsForDecision = Convert-ToDecisionWarningStringArray -Value (Safe-Get -Object $liveLayer -Key 'warnings' -Default @())

    $lastSuccessStage = 'INPUT_VALIDATION'
    $currentStage = 'DECISION_BUILD'
    $decisionRich = Build-DecisionLayer -ResolvedMode $resolvedMode -SourceLayer $sourceLayer -LiveLayer $liveLayer -MissingInputs @($missingInputs) -Warnings $warningsForDecision
    $decision = Convert-ToLegacyDecisionShape -DecisionRich $decisionRich
    $lastSuccessStage = 'DECISION_BUILD'
    if ($liveLayer.enabled) {
        $contradictionSummaryNode = Safe-Get -Object $decision -Key 'contradiction_summary' -Default @{}
        $liveSummary = $liveLayer.summary

        if ($liveSummary -is [System.Collections.IDictionary]) {
            $liveSummary['contradiction_summary'] = $contradictionSummaryNode
        }
        elseif ($liveSummary -is [PSCustomObject]) {
            if ($null -ne $liveSummary.PSObject.Properties['contradiction_summary']) {
                $liveSummary.contradiction_summary = $contradictionSummaryNode
            }
            else {
                $liveSummary | Add-Member -NotePropertyName 'contradiction_summary' -NotePropertyValue $contradictionSummaryNode -Force
            }
        }
        else {
            $liveSummary = @{
                contradiction_summary = $contradictionSummaryNode
            }
            $liveLayer.summary = $liveSummary
        }
    }

    $blockingMissingInputs = @($missingInputs | Where-Object { $_ -ne $null -and -not [string]::Equals([string]$_, 'primary_targets', [System.StringComparison]::OrdinalIgnoreCase) })

    $status = 'PASS'
    if ($blockingMissingInputs.Count -gt 0) { $status = 'FAIL' }
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

    $currentStage = 'OPERATOR_OUTPUT_CONTRACT'
    $runFinishedAt = (Get-Date).ToString('o')
    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus $status -AuditResult $auditResult -Decision $decision -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage -RunFinishedAt $runFinishedAt -FailureReason ''
    $lastSuccessStage = 'OPERATOR_OUTPUT_CONTRACT'
    $currentStage = 'COMPLETE'
}
catch {
    $global:AuditError = $_
    $status = 'FAIL'
    $caughtException = $null
    $caughtInvocationInfo = $null
    $caughtScriptStackTrace = ''
    $caughtRawError = ''
    $caughtExceptionMessage = ''
    try { $caughtException = $_.Exception } catch {}
    if ($null -eq $caughtException) {
        $caughtException = Safe-Get -Object $_ -Key 'Exception' -Default $null
    }
    try { $caughtInvocationInfo = $_.InvocationInfo } catch {}
    if ($null -eq $caughtInvocationInfo) {
        $caughtInvocationInfo = Safe-Get -Object $_ -Key 'InvocationInfo' -Default $null
    }
    try { $caughtScriptStackTrace = [string]$_.ScriptStackTrace } catch {}
    if ([string]::IsNullOrWhiteSpace($caughtScriptStackTrace)) {
        $caughtScriptStackTrace = [string](Safe-Get -Object $_ -Key 'ScriptStackTrace' -Default '')
    }
    try { $caughtRawError = [string]($_ | Out-String) } catch {}
    try { $caughtExceptionMessage = [string](Safe-Get -Object $caughtException -Key 'Message' -Default '') } catch {}
    if ([string]::IsNullOrWhiteSpace($caughtExceptionMessage) -and $null -ne $caughtException) {
        try { $caughtExceptionMessage = [string]$caughtException.Message } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($caughtExceptionMessage)) {
        $caughtExceptionMessage = [string]$caughtRawError
    }
    if ([string]::IsNullOrWhiteSpace($caughtExceptionMessage)) {
        try { $caughtExceptionMessage = [string]$_ } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($caughtExceptionMessage)) {
        $caughtExceptionMessage = 'SITE_AUDITOR runtime failure.'
    }
    $caughtStackHint = ''
    try { $caughtStackHint = [string]$caughtScriptStackTrace } catch {}
    if ([string]::IsNullOrWhiteSpace($caughtStackHint)) {
        $caughtStackHint = [string](Safe-Get -Object $caughtInvocationInfo -Key 'PositionMessage' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($caughtStackHint)) {
        $caughtStackHint = [string](Safe-Get -Object $_ -Key 'ScriptStackTrace' -Default '')
    }
    $caughtOperationLabel = ''
    $caughtFunctionName = ''
    $caughtFailureStage = ''
    $caughtFailureNode = ''
    if ($null -ne $global:DecisionForensics) {
        $caughtFailureStage = [string](Safe-Get -Object $global:DecisionForensics -Key 'failure_stage' -Default '')
        $caughtOperationLabel = [string](Safe-Get -Object $global:DecisionForensics -Key 'activeOperationLabel' -Default '')
        $caughtFunctionName = [string](Safe-Get -Object $global:DecisionForensics -Key 'function_name' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($caughtOperationLabel) -and $null -ne $global:PageQualityForensics) {
        $caughtFailureStage = [string](Safe-Get -Object $global:PageQualityForensics -Key 'failure_stage' -Default $caughtFailureStage)
        $caughtOperationLabel = [string](Safe-Get -Object $global:PageQualityForensics -Key 'activeOperationLabel' -Default '')
        $caughtFunctionName = [string](Safe-Get -Object $global:PageQualityForensics -Key 'function_name' -Default $caughtFunctionName)
    }
    if ([string]::IsNullOrWhiteSpace($caughtFailureStage)) {
        $caughtFailureStage = [string]$currentStage
    }
    if ([string]::IsNullOrWhiteSpace($caughtOperationLabel)) {
        try { $caughtOperationLabel = [string]$activeOperationLabel } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($caughtFunctionName)) {
        try { $caughtFunctionName = [string]$activeFunctionName } catch {}
    }

    $caughtFailureNodeParts = New-Object System.Collections.Generic.List[string]
    foreach ($nodePart in @($caughtFailureStage, $caughtFunctionName, $caughtOperationLabel)) {
        $nodePartText = [string]$nodePart
        if ([string]::IsNullOrWhiteSpace($nodePartText)) { continue }
        $caughtFailureNodeParts.Add($nodePartText)
    }
    if ($caughtFailureNodeParts.Count -gt 0) {
        $caughtFailureNode = [string]::Join('/', @($caughtFailureNodeParts.ToArray()))
    }
    if ([string]::IsNullOrWhiteSpace($caughtFailureNode) -and -not [string]::IsNullOrWhiteSpace([string]$currentStage)) {
        $caughtFailureNode = [string]$currentStage
    }

    try { Write-Host "[TRACE] FAIL NODE: $caughtFailureNode" } catch {}
    try { Write-Host "[TRACE] RAW ERROR: $($caughtRawError)" } catch {}
    try { Write-Host "[TRACE] ERROR: $caughtExceptionMessage" } catch {}

    $failureCore = Resolve-FailureCoreFacts -ErrorRecord $global:AuditError -FailureReason $failureReason
    $failureReason = [string](Safe-Get -Object $failureCore -Key 'error_message' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($caughtExceptionMessage)) {
        $failureReason = $caughtExceptionMessage
    }
    if ([string]::IsNullOrWhiteSpace($failureReason)) {
        $failureReason = "Failure during $caughtFailureStage."
        if (-not [string]::IsNullOrWhiteSpace($caughtStackHint)) {
            $failureReason = "$failureReason Stack: $caughtStackHint"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($caughtFailureNode) -and $failureReason -notmatch [regex]::Escape("[$caughtFailureNode]")) {
        $failureReason = "$failureReason [$caughtFailureNode]"
    }

    if (-not [string]::IsNullOrWhiteSpace($caughtFailureNode)) {
        $currentStage = [string]$caughtFailureNode
    }
    elseif ([string]::IsNullOrWhiteSpace($currentStage)) {
        $currentStage = 'RUNTIME_FAILURE'
    }

    $sourceLayer = New-SourceLayer -Overrides $sourceLayer
    $liveLayer = New-LiveLayer -Overrides $liveLayer

    $decision = @{
        core_problem = $failureReason
        p0 = @($failureReason)
        p1 = @($warnings)
        p2 = @()
        do_next = @('Resolve the failure reason and rerun SITE_AUDITOR.')
        problems = [string]$failureReason
        next_actions = [string]'Resolve the failure reason and rerun SITE_AUDITOR.'
        inputs = Normalize-ToArray @($requiredInputs)
        site_diagnosis = @{
            class = 'BROKEN_SYSTEM'
            reason = 'Run failed before reliable live evidence could be evaluated.'
            evidence = @("failure_reason=$failureReason")
            confidence = 'LOW'
        }
        maturity_readiness = @{
            class = 'NOT_READY'
            reason = 'Auditor run failed before deterministic readiness evidence could be completed.'
            evidence = @("failure_reason=$failureReason")
            confidence = 'LOW'
        }
        contradiction_summary = @{
            route_candidates = @()
            site_candidates = @()
            candidates = @()
            class_counts = @{}
            total_candidates = 0
            route_candidate_count = 0
            site_candidate_count = 0
        }
        clean_state = 'NOT_CLEAN'
        product_closeout = Normalize-ProductCloseout -Value @{
            class = 'BLOCKED_BY_DIAGNOSTIC'
            reason = 'Product closeout classification unavailable because DECISION_BUILD failed before closeout synthesis.'
            confidence = 'low'
            checks = @(
                @{
                    name = 'closeout_classification'
                    status = 'FAIL'
                    detail = 'decision_build_failure'
                }
            )
            evidence = @(
                "failure_reason=$failureReason",
                "stage=$currentStage"
            )
        }
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

    if ([string]::IsNullOrWhiteSpace($currentStage)) { $currentStage = 'RUNTIME_FAILURE' }
    $runFinishedAt = (Get-Date).ToString('o')
    Write-OperatorOutputs -ResolvedMode $resolvedMode -FinalStatus 'FAIL' -AuditResult $auditResult -Decision $decision -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage -RunFinishedAt $runFinishedAt -FailureReason $failureReason
}
finally {
    if ([string]::IsNullOrWhiteSpace($runFinishedAt)) { $runFinishedAt = (Get-Date).ToString('o') }
    Ensure-OutputContract -ResolvedMode $resolvedMode -FinalStatus $status -FailureReason $failureReason
}

if ($status -eq 'PASS' -and $null -eq $global:AuditError) {
    Write-Host "SITE_AUDITOR completed successfully. Artifacts: $outboxDir ; $reportsDir"
    exit 0
}

Write-Host "SITE_AUDITOR failed. Artifacts: $outboxDir ; $reportsDir"
exit 1

# --- DECISION HARD LOCK ---
try {
    if ($runReport -and $runReport.visual_artifacts -and $runReport.visual_artifacts.screenshots_packaged -gt 0) {
        if (-not $decision) { $decision = @{} }

        $decision["CORE_PROBLEM"] = "Site has structural/UX issues detected via visual audit evidence"
        $decision["P0"] = @(
            "UI contamination present",
            "Empty or low-content blocks detected",
            "Conversion path unclear"
        )
        $decision["DO_NEXT"] = @(
            "Remove UI contamination elements",
            "Fill empty blocks with real content",
            "Add clear CTA per page"
        )
    }
}
catch {
    Write-Host "DECISION_LOCK_FAIL"
}

# --- DECISION BUILDER v1 ---
try {
    if ($runReport -and $runReport.visual_artifacts) {

        $va = $runReport.visual_artifacts
        $decision = @{}

        if ($va.screenshots_packaged -gt 0) {

            $decision["CORE_PROBLEM"] = "Detected structural and UX issues based on visual audit evidence"

            $p0 = @()

            if ($va.routes_with_evidence -gt 0) {
                $p0 += "Multiple pages contain visible UX/content issues"
            }

            if ($va.screenshots_packaged -gt 10) {
                $p0 += "Issues appear across multiple sections of the site"
            }

            $decision["P0"] = $p0

            $decision["DO_NEXT"] = @(
                "Review screenshots and identify broken or empty sections",
                "Fix content gaps on affected pages",
                "Add clear CTA blocks on main pages"
            )
        }

        $runReport["decision"] = $decision
    }
}
catch {
    Write-Host "DECISION_BUILDER_FAIL"
}

# --- DECISION BUILDER v2 (signal-based) ---
try {
    if ($auditResultNode) {

        $decision = @{}
        $p0 = @()

        $visual = $auditResultNode["visual_coverage"]
        $content = $auditResultNode["content_analysis"]

        if ($visual -and $visual.screenshots_packaged -gt 0) {

            $decision["CORE_PROBLEM"] = "Site has visible UX/content issues confirmed by audit signals"

            if ($content -and $content.empty_routes -gt 0) {
                $p0 += "Some pages are empty or lack meaningful content"
            }

            if ($visual.contamination_flags) {
                $p0 += "UI contamination elements detected (e.g. 'Built with', debug overlays)"
            }

            if ($visual.routes_with_evidence -gt 3) {
                $p0 += "Issues affect multiple pages across the site"
            }

            if ($p0.Count -eq 0) {
                $p0 += "General UX issues detected but require manual review"
            }

            $decision["P0"] = $p0

            $decision["DO_NEXT"] = @(
                "Fix empty or low-content pages",
                "Remove UI contamination elements",
                "Improve structure and clarity of key pages"
            )
        }

        $runReport["decision"] = $decision
    }
}
catch {
    Write-Host "DECISION_BUILDER_V2_FAIL"
}
