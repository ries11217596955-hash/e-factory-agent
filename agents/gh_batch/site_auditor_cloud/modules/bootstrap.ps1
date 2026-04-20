function Initialize-SiteAuditorBootstrapContext {
    param(
        [string]$ScriptRoot,
        [string]$Workspace = $env:GITHUB_WORKSPACE,
        [int]$ProcessId = $PID
    )

    $base = $ScriptRoot
    if (-not [string]::IsNullOrWhiteSpace($Workspace)) {
        $base = Join-Path $Workspace 'agents/gh_batch/site_auditor_cloud'
    }

    Write-Host "OUTPUT BASE: $base"
    Write-Host "DEBUG BASE PATH: $base"
    Write-Host "DEBUG PWD: $(Get-Location)"

    $timestamp = (Get-Date).ToString('o')

    $global:AuditError = $null
    $global:RouteNormalizationForensics = $null
    $global:RouteNormalizationTrace = @()
    $global:RouteNormalizationAggregateTrace = @()
    $global:PageQualityForensics = $null
    $global:DecisionForensics = $null

    return [ordered]@{
        base = $base
        outboxDir = Join-Path $base 'outbox'
        reportsDir = Join-Path $base 'reports'
        runtimeDir = Join-Path $base 'runtime'
        zipWorkRoot = Join-Path (Join-Path $base 'runtime') 'zip_extracted'
        timestamp = $timestamp
        runStartedAt = $timestamp
        runFinishedAt = $null
        runId = "SITE_AUDITOR_$((Get-Date).ToString('yyyyMMdd_HHmmss_fff'))_$ProcessId"
        currentStage = 'INIT'
        lastSuccessStage = 'INIT'
        status = 'FAIL'
        failureReason = $null
        reportFiles = New-Object System.Collections.Generic.List[string]
    }
}
