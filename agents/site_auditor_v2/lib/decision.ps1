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

    if ($null -eq $RoutesSummary -or -not $RoutesSummary.PSObject.Properties['routes']) {
        throw 'ROUTES_SUMMARY_INVALID: missing routes property.'
    }
    if ($null -eq $AuditSummary) {
        throw 'AUDIT_SUMMARY_INVALID: object is null.'
    }

    if (-not $AuditSummary.PSObject.Properties['total']) {
        Write-Host "AUDIT_SUMMARY: total missing, fallback to routes count"
    }
    if ($null -eq $LinkSummary -or -not $LinkSummary.PSObject.Properties['status']) {
        throw 'LINK_SUMMARY_INVALID: missing status property.'
    }

    $routes = @($RoutesSummary.routes)
    $routeCount = [int]$routes.Count
    if ($routeCount -le 0) {
        $routeCount = Get-IntOrDefault -Value $AuditSummary.total -Default 0
    }

    $brokenCount = if ($AuditSummary.PSObject.Properties['broken']) {
        Get-IntOrDefault -Value $AuditSummary.broken -Default 0
    }
    else {
        [int]@($routes | Where-Object { [string]$_.classification -eq 'broken' }).Count
    }

    $strongCtaCount = [int]@(
        $routes | Where-Object {
            $_.PSObject.Properties['first_screen_has_action'] -and [bool]$_.first_screen_has_action
        }
    ).Count

    $captureMissing = $false
    $routeOverflow = $false
    $captureStatus = ''
    if ($null -ne $Limitations) {
        if ($Limitations.PSObject.Properties['capture_missing']) {
            $captureMissing = [bool]$Limitations.capture_missing
        }
        if ($Limitations.PSObject.Properties['route_overflow']) {
            $routeOverflow = [bool]$Limitations.route_overflow
        }
        if ($Limitations.PSObject.Properties['capture_status']) {
            $captureStatus = [string]$Limitations.capture_status
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
