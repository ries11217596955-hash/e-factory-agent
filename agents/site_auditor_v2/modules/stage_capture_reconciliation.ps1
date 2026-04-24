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

    $selectedRoutesArray = @($SelectedRoutes)
    $manifestPagesArray = @($ManifestPages)

    $selectedRouteKeys = New-CaseInsensitiveKeyMap
    $routeNormalizationErrors = New-SafeList -TypeName 'object'
    foreach ($target in $selectedRoutesArray) {
        $selectedRouteValue = if (-not [string]::IsNullOrWhiteSpace([string]$target.route)) { [string]$target.route } else { [string]$target.url }
        $canonicalResult = Get-CanonicalRouteKeyResult -RouteValue $selectedRouteValue -BaseUrl $BaseUrl
        if ($canonicalResult.status -eq 'ok') {
            $null = Add-KeyIfMissing -Map $selectedRouteKeys -Key ([string]$canonicalResult.canonical_route)
        }
        else {
            $routeNormalizationErrors.Add([ordered]@{ source = 'selected_route'; value = $selectedRouteValue; error = [string]$canonicalResult.error })
        }
    }
    Write-Host 'RECON_PREP: SELECTED_KEYS_DONE'

    $manifestRouteKeys = New-CaseInsensitiveKeyMap
    foreach ($manifestPage in $manifestPagesArray) {
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
    Write-Host 'RECON_PREP: MANIFEST_KEYS_DONE'

    $missingManifestRoutesArray = @(Get-KeyMapKeys -Map $selectedRouteKeys | Where-Object { -not (Test-KeyExists -Map $manifestRouteKeys -Key ([string]$_)) })
    $extraManifestRoutesArray = @(Get-KeyMapKeys -Map $manifestRouteKeys | Where-Object { -not (Test-KeyExists -Map $selectedRouteKeys -Key ([string]$_)) })
    $routeNormalizationErrorsArray = @($routeNormalizationErrors.ToArray())
    $normalizationErrorDetected = ($routeNormalizationErrorsArray.Count -gt 0)
    $counterMismatchDetected = ($normalizationErrorDetected -or $SelectedRoutesCount -ne $ManifestRequestedPages -or $manifestPagesArray.Count -ne $SelectedRoutesCount -or $missingManifestRoutesArray.Count -gt 0 -or $extraManifestRoutesArray.Count -gt 0)
    Write-Host 'RECON_PREP: ROUTE_DIFF_DONE'

    $capturesList = New-SafeList -TypeName 'object'
    foreach ($manifestPage in $manifestPagesArray) {
        foreach ($capture in @($manifestPage.captures)) {
            $capturesList.Add($capture)
        }
    }
    $capturesArray = @($capturesList.ToArray())
    $okCapturesArray = @($capturesArray | Where-Object { $_.status -eq 'ok' })
    $failedCapturesArray = @($capturesArray | Where-Object { $_.status -ne 'ok' })
    $successfulPagesArray = @(
        $manifestPagesArray |
        Where-Object {
            $pageCapturesArray = @($_.captures)
            $okPageCapturesArray = @($pageCapturesArray | Where-Object { $_.status -eq 'ok' })
            $okPageCapturesArray.Count -gt 0
        }
    )

    $capturesAttempted = [int]$capturesArray.Count
    $capturesSuccess = [int]$okCapturesArray.Count
    $capturesFailed = [int]($capturesAttempted - $capturesSuccess)
    $pagesSuccess = [int]$successfulPagesArray.Count
    Write-Host 'RECON_PREP: CAPTURE_COUNTS_DONE'

    $failTypes = New-CaseInsensitiveKeyMap
    foreach ($capture in $failedCapturesArray) {
        if (-not [string]::IsNullOrWhiteSpace([string]$capture.status)) { $null = Add-KeyIfMissing -Map $failTypes -Key ([string]$capture.status) }
    }
    foreach ($manifestPage in ($manifestPagesArray | Where-Object { $_.status -eq 'FAIL' })) { $null = Add-KeyIfMissing -Map $failTypes -Key 'render_fail' }

    $captureReportStatus = 'PASS'
    if ($pagesSuccess -eq 0) { $captureReportStatus = 'FAIL' }
    elseif ($capturesFailed -gt 0) { $captureReportStatus = 'PARTIAL' }

    $selectedRouteKeyCount = [int](Get-KeyMapCount -Map $selectedRouteKeys)
    $manifestRouteKeyCount = [int](Get-KeyMapCount -Map $manifestRouteKeys)
    $failTypesArray = @(Get-KeyMapKeys -Map $failTypes)
    Write-Host 'RECON_PREP: RETURN_READY'

    return [ordered]@{
        counter_mismatch_detected = [bool]$counterMismatchDetected
        normalization_error_detected = [bool]$normalizationErrorDetected
        route_normalization_errors = @($routeNormalizationErrorsArray)
        missing_manifest_routes = @($missingManifestRoutesArray)
        extra_manifest_routes = @($extraManifestRoutesArray)
        selected_route_key_count = [int]$selectedRouteKeyCount
        manifest_route_key_count = [int]$manifestRouteKeyCount
        captures_attempted = [int]$capturesAttempted
        captures_success = [int]$capturesSuccess
        captures_failed = [int]$capturesFailed
        pages_attempted = [int]$SelectedRoutesCount
        pages_processed = [int]$ManifestProcessedPages
        pages_failed = [int]$ManifestFailedPages
        pages_success = [int]$pagesSuccess
        fail_types = @($failTypesArray)
        capture_report_status = [string]$captureReportStatus
    }
}
