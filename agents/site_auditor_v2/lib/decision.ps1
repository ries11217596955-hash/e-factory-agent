# Runtime Contract: Windows PowerShell 5.1 compatible
Set-StrictMode -Version Latest

function Get-IntOrDefault {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [int]$Default
    )

    if ($null -eq $Value) { return [int]$Default }
    try {
        return [int]$Value
    }
    catch {
        return [int]$Default
    }
}

function Test-ObjectHasKey {
    param(
        [Parameter(Mandatory = $false)]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Key)) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return [bool]$InputObject.Contains($Key)
    }

    if ($InputObject.PSObject -and $InputObject.PSObject.Properties) {
        return ($null -ne $InputObject.PSObject.Properties[$Key])
    }

    return $false
}

function Get-ObjectValueOrDefault {
    param(
        [Parameter(Mandatory = $false)]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $false)]
        [object]$Default = $null
    )

    if (-not (Test-ObjectHasKey -InputObject $InputObject -Key $Key)) {
        return $Default
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject[$Key]
    }

    return $InputObject.$Key
}

function Resolve-MinimalDecision {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [Parameter(Mandatory = $true)]
        [object]$AuditSummary,
        [Parameter(Mandatory = $true)]
        [object]$LinkSummary,
        [Parameter(Mandatory = $false)]
        [string]$RoutesSummaryPath,
        [Parameter(Mandatory = $false)]
        [string]$AuditSummaryPath,
        [Parameter(Mandatory = $false)]
        [string]$LinkSummaryPath,
        [Parameter(Mandatory = $false)]
        [object]$Limitations
    )

    $routeThreshold = 4

    if (-not [string]::IsNullOrWhiteSpace($RoutesSummaryPath)) {
        if (-not (Test-Path -LiteralPath $RoutesSummaryPath -PathType Leaf)) {
            throw "ROUTES_SUMMARY_NOT_FOUND: $RoutesSummaryPath"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AuditSummaryPath)) {
        if (-not (Test-Path -LiteralPath $AuditSummaryPath -PathType Leaf)) {
            throw "AUDIT_SUMMARY_NOT_FOUND: $AuditSummaryPath"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($LinkSummaryPath)) {
        if (-not (Test-Path -LiteralPath $LinkSummaryPath -PathType Leaf)) {
            throw "LINK_SUMMARY_NOT_FOUND: $LinkSummaryPath"
        }
    }

    if (-not (Test-ObjectHasKey -InputObject $RoutesSummary -Key 'routes')) {
        throw 'ROUTES_SUMMARY_INVALID: missing routes property.'
    }
    if (-not (Test-ObjectHasKey -InputObject $AuditSummary -Key 'total')) {
        throw 'AUDIT_SUMMARY_INVALID: missing total property.'
    }
    if (-not (Test-ObjectHasKey -InputObject $LinkSummary -Key 'status')) {
        throw 'LINK_SUMMARY_INVALID: missing status property.'
    }

    $routes = @(Get-ObjectValueOrDefault -InputObject $RoutesSummary -Key 'routes' -Default @())
    $routeCount = [int]$routes.Count
    if ($routeCount -le 0) {
        $routeCount = Get-IntOrDefault -Value (Get-ObjectValueOrDefault -InputObject $AuditSummary -Key 'total' -Default $null) -Default 0
    }

    $brokenCount = if (Test-ObjectHasKey -InputObject $AuditSummary -Key 'broken') {
        Get-IntOrDefault -Value (Get-ObjectValueOrDefault -InputObject $AuditSummary -Key 'broken' -Default $null) -Default 0
    }
    else {
        [int]@($routes | Where-Object { [string]$_.classification -eq 'broken' }).Count
    }

    $strongCtaCount = [int]@(
        $routes | Where-Object {
            (Test-ObjectHasKey -InputObject $_ -Key 'first_screen_has_action') -and [bool](Get-ObjectValueOrDefault -InputObject $_ -Key 'first_screen_has_action' -Default $false)
        }
    ).Count

    $captureMissing = $false
    $routeOverflow = $false
    $captureStatus = ''
    if ($null -ne $Limitations) {
        if (Test-ObjectHasKey -InputObject $Limitations -Key 'capture_missing') {
            $captureMissing = [bool](Get-ObjectValueOrDefault -InputObject $Limitations -Key 'capture_missing' -Default $false)
        }
        if (Test-ObjectHasKey -InputObject $Limitations -Key 'route_overflow') {
            $routeOverflow = [bool](Get-ObjectValueOrDefault -InputObject $Limitations -Key 'route_overflow' -Default $false)
        }
        if (Test-ObjectHasKey -InputObject $Limitations -Key 'capture_status') {
            $captureStatus = [string](Get-ObjectValueOrDefault -InputObject $Limitations -Key 'capture_status' -Default '')
        }
    }

    $coreProblem = 'No blocking problem in sampled scope.'
    if ($strongCtaCount -eq 0) {
        $coreProblem = 'No clear action path.'
    }
    elseif ($routeCount -lt $routeThreshold) {
        $coreProblem = 'Surface too shallow.'
    }

    $p0List = New-Object System.Collections.Generic.List[string]
    if ($brokenCount -gt 0) {
        $p0List.Add("Broken navigation: $brokenCount route(s) return non-200.")
    }
    if ($captureMissing -or $captureStatus -eq 'FAIL') {
        $p0List.Add('No visual verification: screenshot evidence is missing.')
    }
    if ($strongCtaCount -eq 0) {
        $p0List.Add('No primary CTA on sampled first screens.')
    }
    if ($routeCount -lt $routeThreshold -and $p0List.Count -lt 3) {
        $p0List.Add("Surface too shallow: only $routeCount routes sampled.")
    }

    $doNextList = New-Object System.Collections.Generic.List[string]
    if ($brokenCount -gt 0) {
        $doNextList.Add('Fix non-200 internal routes in ROUTES_SUMMARY.json and rerun LINK mode.')
    }
    if ($captureMissing -or $captureStatus -eq 'FAIL') {
        $doNextList.Add('Restore screenshot capture toolchain and rerun to regenerate visual_manifest.json.')
    }
    if ($strongCtaCount -eq 0) {
        $doNextList.Add('Add one above-the-fold primary CTA on the homepage, then rerun the audit.')
    }
    if ($routeCount -lt $routeThreshold -and $doNextList.Count -lt 3) {
        $doNextList.Add('Increase checked route count to at least 4 and rerun LINK mode.')
    }
    if ($routeOverflow -and $doNextList.Count -lt 3) {
        $doNextList.Add('Review overflow routes from RUN_REPORT.run_budget and audit the top 3 missed pages.')
    }
    if ($doNextList.Count -eq 0) {
        $doNextList.Add('Keep current scope and rerun LINK mode after next site change.')
    }

    return [ordered]@{
        core_problem = [string]$coreProblem
        p0 = @($p0List | Select-Object -First 3)
        do_next = @($doNextList | Select-Object -First 3)
    }
}
