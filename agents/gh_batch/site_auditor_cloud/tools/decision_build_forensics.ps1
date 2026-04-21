[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SnapshotPath = (Join-Path $PSScriptRoot 'decision_build_snapshot.example.json'),

    [Parameter(Mandatory = $false)]
    [string]$DiagnosticPath,

    [Parameter(Mandatory = $false)]
    [switch]$EmitDecisionJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ForensicsEvents = New-Object System.Collections.Generic.List[object]
$script:CapturedDecisionForensics = @()
$script:CurrentStepLabel = 'initialize'

if ([string]::IsNullOrWhiteSpace($DiagnosticPath)) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $DiagnosticPath = Join-Path $PSScriptRoot ("decision_build_forensics_$stamp.json")
}

$diagnosticDir = Split-Path -Parent $DiagnosticPath
if (-not [string]::IsNullOrWhiteSpace($diagnosticDir) -and -not (Test-Path -LiteralPath $diagnosticDir)) {
    New-Item -ItemType Directory -Path $diagnosticDir -Force | Out-Null
}

function Safe-Get {
    param(
        [object]$Object,
        [object]$Key,
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Key)) { return $Object[$Key] }
        $keyText = [string]$Key
        if ($Object.Contains($keyText)) { return $Object[$keyText] }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Key]
    if ($null -ne $property) {
        return $property.Value
    }

    return $Default
}

function Get-SafeCount {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value.Length }
    if ($Value -is [System.Collections.ICollection]) { return $Value.Count }
    if ($Value -is [System.Collections.IEnumerable]) {
        $count = 0
        foreach ($item in $Value) {
            $count++
            if ($count -ge 100000) { break }
        }
        return $count
    }

    return $null
}

function Get-ObjectDiagnostics {
    param(
        [string]$Name,
        [object]$Value
    )

    $typeName = if ($null -eq $Value) { '<null>' } else { $Value.GetType().FullName }
    $isDictionary = ($Value -is [System.Collections.IDictionary])
    $isEnumerable = ($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])

    $sampleKeys = @()
    if ($isDictionary) {
        $sampleKeys = @($Value.Keys | Select-Object -First 8 | ForEach-Object { [string]$_ })
    }
    elseif ($Value -is [PSCustomObject]) {
        $sampleKeys = @($Value.PSObject.Properties.Name | Select-Object -First 8 | ForEach-Object { [string]$_ })
    }

    return [ordered]@{
        variable_name = [string]$Name
        type = [string]$typeName
        is_null = [bool]($null -eq $Value)
        is_idictionary = [bool]$isDictionary
        is_ienumerable = [bool]$isEnumerable
        is_scalar = [bool](-not $isDictionary -and -not $isEnumerable)
        safe_count = Get-SafeCount -Value $Value
        sample_keys = @($sampleKeys)
    }
}

function Write-DiagnosticEvent {
    param(
        [string]$StepLabel,
        [string]$FunctionName,
        [string[]]$InputVariableNames,
        [hashtable[]]$VariableDiagnostics,
        [object]$Extra = $null
    )

    $event = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        step_label = [string]$StepLabel
        function_name = [string]$FunctionName
        input_variable_names = @($InputVariableNames)
        variable_diagnostics = @($VariableDiagnostics)
    }
    if ($null -ne $Extra) {
        $event.extra = $Extra
    }

    [void]$script:ForensicsEvents.Add($event)
    $json = $event | ConvertTo-Json -Depth 20 -Compress
    Add-Content -LiteralPath $DiagnosticPath -Value $json
}

function Set-DecisionForensics {
    param(
        [string]$FunctionName,
        [string]$ActivePhase,
        [string]$ActiveOperationLabel,
        [string]$ActiveExpression,
        [object]$LeftOperand,
        [object]$RightOperand,
        [string]$StackHintIfAvailable,
        [object]$AdditionalContext
    )

    $record = [ordered]@{
        function_name = [string]$FunctionName
        active_phase = [string]$ActivePhase
        active_operation_label = [string]$ActiveOperationLabel
        active_expression = [string]$ActiveExpression
        left_operand_type = if ($null -eq $LeftOperand) { '<null>' } else { $LeftOperand.GetType().FullName }
        right_operand_type = if ($null -eq $RightOperand) { '<null>' } else { $RightOperand.GetType().FullName }
        left_operand_count = Get-SafeCount -Value $LeftOperand
        right_operand_count = Get-SafeCount -Value $RightOperand
        stack_hint = [string]$StackHintIfAvailable
        additional_context = $AdditionalContext
        captured_utc = (Get-Date).ToUniversalTime().ToString('o')
    }

    $script:CapturedDecisionForensics = @($script:CapturedDecisionForensics) + @($record)
    Write-DiagnosticEvent -StepLabel ([string]$ActiveOperationLabel) -FunctionName ([string]$FunctionName) -InputVariableNames @('LeftOperand', 'RightOperand') -VariableDiagnostics @(
        (Get-ObjectDiagnostics -Name 'LeftOperand' -Value $LeftOperand),
        (Get-ObjectDiagnostics -Name 'RightOperand' -Value $RightOperand)
    ) -Extra ([ordered]@{
        active_phase = [string]$ActivePhase
        active_expression = [string]$ActiveExpression
        additional_context = $AdditionalContext
    })
}

function Log-Step {
    param(
        [string]$Label,
        [string]$FunctionName,
        [hashtable]$Inputs
    )

    $script:CurrentStepLabel = [string]$Label
    $inputNames = @($Inputs.Keys | ForEach-Object { [string]$_ })
    $diagnostics = @(
        foreach ($key in $inputNames) {
            Get-ObjectDiagnostics -Name $key -Value $Inputs[$key]
        }
    )

    Write-DiagnosticEvent -StepLabel $Label -FunctionName $FunctionName -InputVariableNames $inputNames -VariableDiagnostics $diagnostics
}

function Convert-ToHashtableFromJsonObject {
    param([object]$Value)

    if ($null -eq $Value) { return @{} }
    if ($Value -is [System.Collections.IDictionary]) { return $Value }
    if ($Value -is [PSCustomObject]) {
        $hash = [ordered]@{}
        foreach ($prop in @($Value.PSObject.Properties)) {
            $hash[[string]$prop.Name] = $prop.Value
        }
        return $hash
    }

    return @{}
}

$moduleRoot = Join-Path (Join-Path $PSScriptRoot '..') 'modules'
$forensicsHelperPath = Join-Path $PSScriptRoot 'decision_build_forensics_helpers.ps1'
if (Test-Path -LiteralPath $forensicsHelperPath) {
    . $forensicsHelperPath
}

$moduleFiles = @(
    'util_convert.ps1',
    'decision_diagnosis.ps1',
    'decision_remediation.ps1',
    'decision_closeout.ps1',
    'decision_build.ps1'
)

foreach ($module in $moduleFiles) {
    $modulePath = Join-Path $moduleRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    . $modulePath
}

if (-not (Test-Path -LiteralPath $SnapshotPath)) {
    throw "Snapshot file not found: $SnapshotPath"
}

if (Test-Path -LiteralPath $DiagnosticPath) {
    Remove-Item -LiteralPath $DiagnosticPath -Force
}

function ConvertFrom-JsonCompat {
    param([string]$JsonText)

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return ($JsonText | ConvertFrom-Json -Depth 100)
    }

    return ($JsonText | ConvertFrom-Json)
}

$rawSnapshot = Get-Content -LiteralPath $SnapshotPath -Raw
$snapshot = ConvertFrom-JsonCompat -JsonText $rawSnapshot

$resolvedMode = [string](Safe-Get -Object $snapshot -Key 'resolved_mode' -Default 'live')
$sourceLayer = Convert-ToHashtableFromJsonObject -Value (Safe-Get -Object $snapshot -Key 'source_layer' -Default @{})
$liveLayer = Convert-ToHashtableFromJsonObject -Value (Safe-Get -Object $snapshot -Key 'live_layer' -Default @{})
$missingInputs = @(Safe-Get -Object $snapshot -Key 'missing_inputs' -Default @())
$warnings = @(Safe-Get -Object $snapshot -Key 'warnings' -Default @())

Log-Step -Label 'snapshot_loaded' -FunctionName 'decision_build_forensics.ps1' -Inputs ([ordered]@{
    SnapshotPath = $SnapshotPath
    resolved_mode = $resolvedMode
    source_layer = $sourceLayer
    live_layer = $liveLayer
    missing_inputs = $missingInputs
    warnings = $warnings
})

$runResult = $null
$failureRecord = $null

try {
    $contradictionSummary = [ordered]@{
        class = 'ARTIFACT_TRUTH_ACTIVE'
        total_candidates = 0
        candidates = @()
        class_counts = @{}
        artifact_truth = [ordered]@{
            visual_audit_active = $true
            screenshot_count = [int](Safe-Get -Object (Safe-Get -Object $liveLayer -Key 'summary' -Default @{}) -Key 'screenshot_count' -Default 0)
            routes_with_evidence = [int](Safe-Get -Object (Safe-Get -Object $liveLayer -Key 'summary' -Default @{}) -Key 'routes_with_evidence' -Default 0)
        }
    }

    Log-Step -Label 'site_diagnosis_build' -FunctionName 'Build-SiteDiagnosisLayer' -Inputs ([ordered]@{
        SourceLayer = $sourceLayer
        LiveLayer = $liveLayer
        ContradictionSummary = $contradictionSummary
        MissingInputs = $missingInputs
    })
    $siteDiagnosis = Build-SiteDiagnosisLayer -SourceLayer $sourceLayer -LiveLayer $liveLayer -ContradictionSummary $contradictionSummary -MissingInputs $missingInputs

    Log-Step -Label 'maturity_readiness_build' -FunctionName 'Build-MaturityReadinessLayer' -Inputs ([ordered]@{
        SourceLayer = $sourceLayer
        LiveLayer = $liveLayer
        SiteDiagnosis = $siteDiagnosis
        ContradictionSummary = $contradictionSummary
        MissingInputs = $missingInputs
    })
    $maturityReadiness = Build-MaturityReadinessLayer -SourceLayer $sourceLayer -LiveLayer $liveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary -MissingInputs $missingInputs

    Log-Step -Label 'auditor_baseline_build' -FunctionName 'Build-AuditorBaselineCertification' -Inputs ([ordered]@{
        FinalStatus = 'FAIL'
        SourceLayer = $sourceLayer
        LiveLayer = $liveLayer
        ContradictionSummary = $contradictionSummary
        SiteDiagnosis = $siteDiagnosis
        MaturityReadiness = $maturityReadiness
    })
    $null = Build-AuditorBaselineCertification -FinalStatus 'FAIL' -SourceLayer $sourceLayer -LiveLayer $liveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness

    Log-Step -Label 'primary_remediation_package_build' -FunctionName 'Build-PrimaryRemediationPackage' -Inputs ([ordered]@{
        LiveLayer = $liveLayer
        SiteDiagnosis = $siteDiagnosis
        ContradictionSummary = $contradictionSummary
    })
    $remediationPackage = Build-PrimaryRemediationPackage -LiveLayer $liveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary

    Log-Step -Label 'product_closeout_build' -FunctionName 'Build-ProductCloseoutClassification' -Inputs ([ordered]@{
        FinalStatus = 'FAIL'
        SourceLayer = $sourceLayer
        LiveLayer = $liveLayer
        ContradictionSummary = $contradictionSummary
        SiteDiagnosis = $siteDiagnosis
        MaturityReadiness = $maturityReadiness
        RemediationPackage = $remediationPackage
    })
    $null = Build-ProductCloseoutClassification -FinalStatus 'FAIL' -SourceLayer $sourceLayer -LiveLayer $liveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness -RemediationPackage $remediationPackage

    Log-Step -Label 'decision_layer_build' -FunctionName 'Build-DecisionLayer' -Inputs ([ordered]@{
        ResolvedMode = $resolvedMode
        SourceLayer = $sourceLayer
        LiveLayer = $liveLayer
        MissingInputs = $missingInputs
        Warnings = $warnings
    })
    $runResult = Build-DecisionLayer -ResolvedMode $resolvedMode -SourceLayer $sourceLayer -LiveLayer $liveLayer -MissingInputs $missingInputs -Warnings $warnings

    Write-DiagnosticEvent -StepLabel 'decision_layer_complete' -FunctionName 'Build-DecisionLayer' -InputVariableNames @('decision_result') -VariableDiagnostics @(
        (Get-ObjectDiagnostics -Name 'decision_result' -Value $runResult)
    )
}
catch {
    $message = [string]$_.Exception.Message
    $stackTrace = [string]$_.ScriptStackTrace
    $lastForensics = $null
    if (@($script:CapturedDecisionForensics).Count -gt 0) {
        $lastForensics = @($script:CapturedDecisionForensics)[-1]
    }

    $failureRecord = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        failing_step = if ($null -ne $lastForensics) { [string](Safe-Get -Object $lastForensics -Key 'active_operation_label' -Default $script:CurrentStepLabel) } else { [string]$script:CurrentStepLabel }
        exact_exception_text = $message
        last_active_label = [string]$script:CurrentStepLabel
        stack_trace = $stackTrace
        variable_type_dump = if ($null -ne $lastForensics) { $lastForensics } else { @{} }
    }

    Write-DiagnosticEvent -StepLabel 'exception' -FunctionName 'decision_build_forensics.ps1' -InputVariableNames @('exception') -VariableDiagnostics @() -Extra $failureRecord
}

$artifact = [ordered]@{
    harness = 'decision_build_forensics'
    snapshot_path = $SnapshotPath
    diagnostic_path = $DiagnosticPath
    status = if ($null -eq $failureRecord) { 'SUCCESS' } else { 'FAILURE' }
    required_snapshot_fields = @('resolved_mode', 'source_layer.required', 'source_layer.ok', 'live_layer.required', 'live_layer.ok', 'live_layer.enabled', 'live_layer.summary', 'live_layer.route_details', 'missing_inputs', 'warnings')
    events = @($script:ForensicsEvents)
    captured_decision_forensics = @($script:CapturedDecisionForensics)
    failure = $failureRecord
}

$artifact | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $DiagnosticPath -Encoding UTF8
Write-Host "[forensics] Diagnostic artifact: $DiagnosticPath"
if ($artifact.status -eq 'FAILURE') {
    Write-Host "[forensics] Failure step: $($artifact.failure.failing_step)"
    Write-Host "[forensics] Exception: $($artifact.failure.exact_exception_text)"
}

if ($EmitDecisionJson -and $null -ne $runResult) {
    $resultPath = [System.IO.Path]::ChangeExtension($DiagnosticPath, '.decision.json')
    $runResult | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host "[forensics] Decision output: $resultPath"
}

if ($artifact.status -eq 'FAILURE') {
    exit 1
}

exit 0
