Set-StrictMode -Version Latest

function Invoke-CaptureReconciliationPrepStage {
    param(
        [Parameter(Mandatory = $true)]
        [Object[]]$SelectedRoutes,
        [Parameter(Mandatory = $true)]
        [Object[]]$ManifestPages,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [int]$SelectedRoutesCount,
        [Parameter(Mandatory = $true)]
        [int]$ManifestRequestedPages,
        [Parameter(Mandatory = $true)]
        [int]$ManifestProcessedPages,
        [Parameter(Mandatory = $true)]
        [int]$ManifestFailedPages
    )

    $selectedRouteKeys = New-CaseInsensitiveKeyMap
    $routeNormalizationErrors = New-SafeList -TypeName 'object'
    foreach ($target in $SelectedRoutes) {
        $selectedRouteValue = if (-not [string]::IsNullOrWhiteSpace([string]$target.route)) { [string]$target.route } else { [string]$target.url }
        $canonicalResult = Get-CanonicalRouteKeyResult -RouteValue $selectedRouteValue -BaseUrl $BaseUrl
        if ($canonicalResult.status -eq 'ok') {
            $null = Add-KeyIfMissing -Map $selectedRouteKeys -Key ([string]$canonicalResult.canonical_route)
        }
        else {
            $routeNormalizationErrors.Add([ordered]@{ source = 'selected_route'; value = $selectedRouteValue; error = [string]$canonicalResult.error })
        }
    }

    $manifestRouteKeys = New-CaseInsensitiveKeyMap
    foreach ($manifestPage in $ManifestPages) {
        $manifestPageUrl = if ($manifestPage.PSObject.Properties['url']) { [string]$manifestPage.url } elseif ($manifestPage.PSObject.Properties['source_url']) { [string]$manifestPage.source_url } else { '' }
        if ([string]::IsNullOrWhiteSpace($manifestPageUrl)) { continue }

        $canonicalResult = Get-CanonicalRouteKeyResult -RouteValue $manifestPageUrl -BaseUrl $BaseUrl
        if ($canonicalResult.status -eq 'ok') {
            $null = Add-KeyIfMissing -Map $manifestRouteKeys -Key ([string]$canonicalResult.canonical_route)
        }
        else {
            $routeNormalizationErrors.Add([ordered]@{ source = 'manifest_route'; value = $manifestPageUrl; error = [string]$canonicalResult.error })
        }
    }

    $missingManifestRoutes = @(Get-KeyMapKeys -Map $selectedRouteKeys | Where-Object { -not (Test-KeyExists -Map $manifestRouteKeys -Key ([string]$_)) })
    $extraManifestRoutes = @(Get-KeyMapKeys -Map $manifestRouteKeys | Where-Object { -not (Test-KeyExists -Map $selectedRouteKeys -Key ([string]$_)) })
    $normalizationErrorDetected = ($routeNormalizationErrors.Count -gt 0)
    $counterMismatchDetected = ($normalizationErrorDetected -or $SelectedRoutesCount -ne $ManifestRequestedPages -or $ManifestPages.Count -ne $SelectedRoutesCount -or $missingManifestRoutes.Count -gt 0 -or $extraManifestRoutes.Count -gt 0)

    $captures = @($ManifestPages | ForEach-Object { @($_.captures) })
    $capturesAttempted = [int]$captures.Count
    $capturesSuccess = [int]@($captures | Where-Object { $_.status -eq 'ok' }).Count
    $capturesFailed = [int]($capturesAttempted - $capturesSuccess)
    $pagesSuccess = [int]@($ManifestPages | Where-Object { @($_.captures | Where-Object { $_.status -eq 'ok' }).Count -gt 0 }).Count

    $failTypes = New-CaseInsensitiveKeyMap
    foreach ($capture in ($captures | Where-Object { $_.status -ne 'ok' })) {
        if (-not [string]::IsNullOrWhiteSpace([string]$capture.status)) { $null = Add-KeyIfMissing -Map $failTypes -Key ([string]$capture.status) }
    }
    foreach ($manifestPage in ($ManifestPages | Where-Object { $_.status -eq 'FAIL' })) { $null = Add-KeyIfMissing -Map $failTypes -Key 'render_fail' }

    $captureReportStatus = 'PASS'
    if ($pagesSuccess -eq 0) { $captureReportStatus = 'FAIL' }
    elseif ($capturesFailed -gt 0) { $captureReportStatus = 'PARTIAL' }

    return [ordered]@{
        counter_mismatch_detected = [bool]$counterMismatchDetected
        normalization_error_detected = [bool]$normalizationErrorDetected
        route_normalization_errors = @($routeNormalizationErrors)
        missing_manifest_routes = @($missingManifestRoutes)
        extra_manifest_routes = @($extraManifestRoutes)
        selected_route_key_count = Get-KeyMapCount -Map $selectedRouteKeys
        manifest_route_key_count = Get-KeyMapCount -Map $manifestRouteKeys
        captures_attempted = [int]$capturesAttempted
        captures_success = [int]$capturesSuccess
        captures_failed = [int]$capturesFailed
        pages_attempted = [int]$SelectedRoutesCount
        pages_processed = [int]$ManifestProcessedPages
        pages_failed = [int]$ManifestFailedPages
        pages_success = [int]$pagesSuccess
        fail_types = @(Get-KeyMapKeys -Map $failTypes)
        capture_report_status = [string]$captureReportStatus
    }
}
