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
Write-Host "DEBUG BASE PATH: $base"
Write-Host "DEBUG PWD: $(Get-Location)"

$outboxDir = Join-Path $base 'outbox'
$reportsDir = Join-Path $base 'reports'
$runtimeDir = Join-Path $base 'runtime'
$zipWorkRoot = Join-Path $runtimeDir 'zip_extracted'
$timestamp = (Get-Date).ToString('o')
$runStartedAt = $timestamp
$runFinishedAt = $null
$runId = "SITE_AUDITOR_$((Get-Date).ToString('yyyyMMdd_HHmmss_fff'))_$PID"
$currentStage = 'INIT'
$lastSuccessStage = 'INIT'
$status = 'FAIL'
$failureReason = $null
$global:AuditError = $null
$global:RouteNormalizationForensics = $null
$global:RouteNormalizationTrace = @()
$global:RouteNormalizationAggregateTrace = @()
$global:PageQualityForensics = $null
$global:DecisionForensics = $null
$reportFiles = New-Object System.Collections.Generic.List[string]

function Get-DebugValueSample {
    param(
        [object]$Value,
        [int]$MaxLength = 180
    )

    if ($null -eq $Value) { return '<null>' }

    $text = ''
    if ($Value -is [string]) {
        $text = $Value
    }
    elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        try {
            $text = $Value | ConvertTo-Json -Depth 4 -Compress
        }
        catch {
            $text = [string]$Value
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        try {
            $text = @($Value | Select-Object -First 5 | ForEach-Object { [string]$_ }) -join ', '
        }
        catch {
            $text = [string]$Value
        }
    }
    else {
        $text = [string]$Value
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return '<empty>' }
    if ($text.Length -le $MaxLength) { return $text }
    return "$($text.Substring(0, $MaxLength))..."
}

function Get-ObjectShapeSummary {
    param([object]$Value)

    if ($null -eq $Value) {
        return [ordered]@{
            type = '<null>'
            keys = @()
            property_names = @()
            count = 0
        }
    }

    $keys = @()
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Select-Object -First 20)
    }

    $propertyNames = @($Value.PSObject.Properties.Name | Select-Object -First 20)
    $count = 0
    if ($Value -is [System.Collections.ICollection]) {
        $count = [int]$Value.Count
    }

    return [ordered]@{
        type = $Value.GetType().FullName
        keys = @($keys)
        property_names = @($propertyNames)
        count = $count
    }
}

function Set-RouteNormalizationForensics {
    param(
        [string]$FunctionName,
        [string]$ActivePhase = '',
        [string]$ActiveOperationLabel = '',
        [string]$ActiveExpression = '',
        [string]$OperationLabel = '',
        [string]$Expression,
        [object]$LeftOperand,
        [object]$RightOperand,
        [string[]]$VariableNames = @(),
        [object]$RouteContext = $null,
        [object]$AdditionalContext = $null
    )

    $contextKeys = @()
    if ($RouteContext -is [System.Collections.IDictionary]) {
        $contextKeys = @($RouteContext.Keys | ForEach-Object { [string]$_ } | Select-Object -First 30)
    }
    elseif ($null -ne $RouteContext) {
        $contextKeys = @($RouteContext.PSObject.Properties.Name | Select-Object -First 30)
    }

    $routePath = $null
    if ($null -ne $RouteContext) {
        $routePath = Safe-Get -Object $RouteContext -Key 'route_path' -Default (Safe-Get -Object $RouteContext -Key 'url' -Default $null)
    }
    if ($null -eq $routePath -and $null -ne $AdditionalContext) {
        $routePath = Safe-Get -Object $AdditionalContext -Key 'route_path' -Default $null
    }

    $stackHint = $null
    if ($null -ne $AdditionalContext) {
        $stackHint = Safe-Get -Object $AdditionalContext -Key 'stack_hint' -Default $null
    }

    $leftType = if ($null -eq $LeftOperand) { '<null>' } else { $LeftOperand.GetType().FullName }
    $rightType = if ($null -eq $RightOperand) { '<null>' } else { $RightOperand.GetType().FullName }
    $leftSample = Get-DebugValueSample -Value $LeftOperand
    $rightSample = Get-DebugValueSample -Value $RightOperand

    $global:RouteNormalizationForensics = [ordered]@{
        failure_stage = 'ROUTE_NORMALIZATION'
        function_name = $FunctionName
        activePhase = if ([string]::IsNullOrWhiteSpace($ActivePhase)) { '' } else { $ActivePhase }
        activeOperationLabel = if ([string]::IsNullOrWhiteSpace($ActiveOperationLabel)) { $OperationLabel } else { $ActiveOperationLabel }
        activeExpression = if ([string]::IsNullOrWhiteSpace($ActiveExpression)) { $Expression } else { $ActiveExpression }
        operation_label = $OperationLabel
        expression = $Expression
        variable_names = @($VariableNames)
        left_type = $leftType
        right_type = $rightType
        left_value_sample = $leftSample
        right_value_sample = $rightSample
        context_keys = @($contextKeys)
        route_path_if_available = if ($null -eq $routePath) { '' } else { [string]$routePath }
        stack_hint_if_available = if ($null -eq $stackHint) { '' } else { [string]$stackHint }

        failure_function = $FunctionName
        failure_expression = $Expression
        value_samples = [ordered]@{
            left = $leftSample
            right = $rightSample
        }
        route_context_shape = Get-ObjectShapeSummary -Value $RouteContext
        additional_context = if ($null -eq $AdditionalContext) { @{} } else { $AdditionalContext }
    }
}

function Set-PageQualityForensics {
    param(
        [string]$FunctionName,
        [string]$ActivePhase = 'PAGE_QUALITY_BUILD',
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

    $global:PageQualityForensics = [ordered]@{
        failure_stage = 'PAGE_QUALITY_BUILD'
        function_name = $FunctionName
        activePhase = if ([string]::IsNullOrWhiteSpace($ActivePhase)) { 'PAGE_QUALITY_BUILD' } else { $ActivePhase }
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

function Add-RouteNormalizationTracePhase {
    param(
        [string]$PhaseName,
        [int]$RouteIndex,
        [string]$RoutePathIfAvailable = '',
        [object]$PhaseObject = $null,
        [string]$Status = 'ok',
        [string]$OperationLabel = '',
        [string]$Expression = '',
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null,
        [object]$LeftOperand = $null,
        [object]$RightOperand = $null
    )

    if ($null -eq $global:RouteNormalizationTrace) {
        $global:RouteNormalizationTrace = @()
    }

    $shape = Get-ObjectShapeSummary -Value $PhaseObject
    $entry = [ordered]@{
        phase_name = $PhaseName
        route_index = [int]$RouteIndex
        route_path_if_available = if ([string]::IsNullOrWhiteSpace($RoutePathIfAvailable)) { '' } else { [string]$RoutePathIfAvailable }
        object_type = [string](Safe-Get -Object $shape -Key 'type' -Default '<null>')
        keys = @((Safe-Get -Object $shape -Key 'keys' -Default @()))
        short_value_sample = Get-DebugValueSample -Value $PhaseObject
        status = $Status
    }

    if ($Status -eq 'failed') {
        $leftType = if ($null -eq $LeftOperand) { '<null>' } else { $LeftOperand.GetType().FullName }
        $rightType = if ($null -eq $RightOperand) { '<null>' } else { $RightOperand.GetType().FullName }
        $entry.failure = [ordered]@{
            failing_phase = $PhaseName
            operation_label = $OperationLabel
            expression = if ([string]::IsNullOrWhiteSpace($Expression)) { '' } else { $Expression }
            left_type = $leftType
            right_type = $rightType
            left_value_sample = Get-DebugValueSample -Value $LeftOperand
            right_value_sample = Get-DebugValueSample -Value $RightOperand
            error_message = if ($null -eq $ErrorRecord -or $null -eq $ErrorRecord.Exception) { '' } else { [string]$ErrorRecord.Exception.Message }
            stack_hint_if_available = if ($null -eq $ErrorRecord) { '' } else { [string]$ErrorRecord.ScriptStackTrace }
        }
    }

    $global:RouteNormalizationTrace += $entry
}

function Add-RouteNormalizationAggregateTrace {
    param(
        [string]$PhaseName,
        [string]$OperationLabel = '',
        [string]$Expression,
        [object]$LeftOperand = $null,
        [object]$RightOperand = $null,
        [string]$Status = 'ok',
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )

    if ($null -eq $global:RouteNormalizationAggregateTrace) {
        $global:RouteNormalizationAggregateTrace = @()
    }

    $leftType = if ($null -eq $LeftOperand) { '<null>' } else { $LeftOperand.GetType().FullName }
    $rightType = if ($null -eq $RightOperand) { '<null>' } else { $RightOperand.GetType().FullName }

    $global:RouteNormalizationAggregateTrace += [ordered]@{
        phase_name = $PhaseName
        operation_label = if ([string]::IsNullOrWhiteSpace($OperationLabel)) { '' } else { $OperationLabel }
        object_type = "$leftType|$rightType"
        left_type = $leftType
        right_type = $rightType
        left_value_sample = Get-DebugValueSample -Value $LeftOperand
        right_value_sample = Get-DebugValueSample -Value $RightOperand
        status = $Status
        expression = if ([string]::IsNullOrWhiteSpace($Expression)) { '' } else { $Expression }
        stack_hint_if_available = if ($null -eq $ErrorRecord) { '' } else { [string]$ErrorRecord.ScriptStackTrace }
    }
}

function Get-FirstFailingAggregateTraceEntry {
    if ($null -eq $global:RouteNormalizationAggregateTrace) {
        return $null
    }
    foreach ($entry in @($global:RouteNormalizationAggregateTrace)) {
        $status = [string](Safe-Get -Object $entry -Key 'status' -Default '')
        if ($status -eq 'failed') {
            return $entry
        }
    }
    return $null
}

function Get-LastAggregateTraceEntry {
    if ($null -eq $global:RouteNormalizationAggregateTrace) {
        return $null
    }

    $entries = @($global:RouteNormalizationAggregateTrace)
    if ($entries.Count -le 0) {
        return $null
    }

    return $entries[$entries.Count - 1]
}

function Get-LastRouteNormalizationTracePhaseEntry {
    if ($null -eq $global:RouteNormalizationTrace) {
        return $null
    }

    $entries = @($global:RouteNormalizationTrace)
    if ($entries.Count -le 0) {
        return $null
    }

    return $entries[$entries.Count - 1]
}

function New-RouteNormalizationFallbackDebug {
    param(
        [string]$StackHint = '',
        [string]$FailureMessage = ''
    )

    $fallbackEntry = Get-FirstFailingAggregateTraceEntry
    $fallbackSource = 'aggregate_first_failed'

    if ($null -eq $fallbackEntry) {
        $fallbackEntry = Get-LastAggregateTraceEntry
        $fallbackSource = 'aggregate_last_known'
    }

    if ($null -eq $fallbackEntry) {
        $fallbackEntry = Get-LastRouteNormalizationTracePhaseEntry
        $fallbackSource = 'trace_last_known'
    }

    $fallbackOperationLabel = [string](Safe-Get -Object $fallbackEntry -Key 'operation_label' -Default '')
    $fallbackPhaseName = [string](Safe-Get -Object $fallbackEntry -Key 'phase_name' -Default '')
    $fallbackExpression = [string](Safe-Get -Object $fallbackEntry -Key 'expression' -Default '')
    $fallbackLeftType = [string](Safe-Get -Object $fallbackEntry -Key 'left_type' -Default '<unknown>')
    $fallbackRightType = [string](Safe-Get -Object $fallbackEntry -Key 'right_type' -Default '<unknown>')
    $fallbackLeftSample = [string](Safe-Get -Object $fallbackEntry -Key 'left_value_sample' -Default '<unknown>')
    $fallbackRightSample = [string](Safe-Get -Object $fallbackEntry -Key 'right_value_sample' -Default '<unknown>')

    if ($fallbackSource -eq 'trace_last_known') {
        if ([string]::IsNullOrWhiteSpace($fallbackLeftType)) {
            $fallbackLeftType = [string](Safe-Get -Object $fallbackEntry -Key 'object_type' -Default '<unknown>')
        }
        if ([string]::IsNullOrWhiteSpace($fallbackLeftSample) -or $fallbackLeftSample -eq '<unknown>') {
            $fallbackLeftSample = [string](Safe-Get -Object $fallbackEntry -Key 'short_value_sample' -Default '<unknown>')
        }
        if ([string]::IsNullOrWhiteSpace($fallbackPhaseName)) {
            $fallbackPhaseName = [string](Safe-Get -Object $fallbackEntry -Key 'phase_name' -Default '')
        }
        if ([string]::IsNullOrWhiteSpace($fallbackOperationLabel)) {
            $fallbackOperationLabel = 'TRACE_LAST_KNOWN'
        }
        if ([string]::IsNullOrWhiteSpace($fallbackExpression)) {
            $fallbackExpression = '<derived_from_trace_phase>'
        }
    }

    $resolvedFunctionName = if (
        [string]::IsNullOrWhiteSpace($fallbackOperationLabel) -and
        [string]::IsNullOrWhiteSpace($fallbackPhaseName) -and
        [string]::IsNullOrWhiteSpace($fallbackExpression)
    ) { 'unknown' } else { 'Normalize-LiveRoutes' }

    $resolvedPhase = if ([string]::IsNullOrWhiteSpace($fallbackPhaseName)) { 'unknown' } else { $fallbackPhaseName }
    $resolvedOperation = if ([string]::IsNullOrWhiteSpace($fallbackOperationLabel)) { 'unknown' } else { $fallbackOperationLabel }
    $resolvedExpression = if ([string]::IsNullOrWhiteSpace($fallbackExpression)) { 'unknown' } else { $fallbackExpression }

    return [ordered]@{
        failure_stage = 'ROUTE_NORMALIZATION'
        function_name = $resolvedFunctionName
        activePhase = $resolvedPhase
        activeOperationLabel = $resolvedOperation
        activeExpression = $resolvedExpression
        operation_label = $resolvedOperation
        expression = $resolvedExpression
        variable_names = @()
        left_type = $fallbackLeftType
        right_type = $fallbackRightType
        left_value_sample = $fallbackLeftSample
        right_value_sample = $fallbackRightSample
        context_keys = @()
        route_path_if_available = ''
        stack_hint_if_available = if ([string]::IsNullOrWhiteSpace($StackHint)) { '' } else { $StackHint }
        failure_function = $resolvedFunctionName
        failure_expression = $resolvedExpression
        value_samples = [ordered]@{
            left = $fallbackLeftSample
            right = $fallbackRightSample
        }
        route_context_shape = [ordered]@{
            type = '<unknown>'
            keys = @()
            property_names = @()
            count = 0
        }
        additional_context = [ordered]@{
            fallback_source = if ($null -eq $fallbackEntry) { 'none' } else { $fallbackSource }
            fallback_phase_name = $resolvedPhase
            fallback_operation_label = $resolvedOperation
            fallback_expression = $resolvedExpression
            failure_message = if ([string]::IsNullOrWhiteSpace($FailureMessage)) { '' } else { $FailureMessage }
        }
    }
}


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
    if ($Value -is [object[]]) { return [object[]]$Value }
    if ($Value -is [string[]]) { return [object[]]$Value }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }
    if ($Value -is [System.Collections.Generic.List[object]]) { return [object[]]$Value.ToArray() }
    if ($Value -is [System.Collections.Generic.List[string]]) { return [object[]]$Value.ToArray() }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        return @($Value)
    }
    if ($Value -is [System.Collections.ICollection]) {
        $materialized = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $materialized.Add($item)
        }
        return [object[]]$materialized.ToArray()
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $materialized = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $materialized.Add($item)
        }
        return [object[]]$materialized.ToArray()
    }
    return @($Value)
}

function Normalize-ToArray {
    param([object]$x)

    if ($null -eq $x) { return @() }
    if ($x -is [string]) { return @($x) }
    if ($x -is [System.Collections.IEnumerable]) { return @($x) }
    return @($x)
}

function Normalize-CollectionShape {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) { return @($Value) }
    return Convert-ToObjectArraySafe -Value $Value
}

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if ($null -eq $List) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if (-not ($List.Contains($text))) {
        $List.Add($text)
    }
}

function Convert-ToStringArraySafe {
    param(
        [object]$Value
    )

    $items = Convert-ToObjectArraySafe -Value $Value
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

    if ($normalized.Count -eq 0) { return @() }
    return [string[]]$normalized.ToArray()
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

function Convert-ToStringKeyDictionarySafe {
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return @{} }
    if (-not ($Value -is [System.Collections.IDictionary])) { return $Value }

    $normalized = [ordered]@{}
    foreach ($entry in @($Value.GetEnumerator() | Where-Object { $_ -ne $null })) {
        $keyText = [string](Safe-Get -Object $entry -Key 'Key' -Default '')
        if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
        $normalized[$keyText] = Safe-Get -Object $entry -Key 'Value' -Default $null
    }

    return $normalized
}

function Convert-ToHashtableSafe {
    param([object]$Value)

    if ($null -eq $Value) { return @{} }
if (-not ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject])) {
    Write-Host "[WARN] Convert-ToHashtableSafe fallback triggered. Type: $($Value.GetType().FullName)"
}
    if ($Value -is [System.Collections.IDictionary] -and $Value.Count -gt 0) {
        $normalized = [ordered]@{}
        foreach ($entry in @($Value.GetEnumerator())) {
            $keyText = [string](Safe-Get -Object $entry -Key 'Key' -Default '')
            if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
            $normalized[$keyText] = Safe-Get -Object $entry -Key 'Value' -Default $null
        }
        return $normalized
    }

    if ($Value -is [PSCustomObject]) {
        $normalized = [ordered]@{}
        foreach ($prop in @($Value.PSObject.Properties)) {
            if ($null -eq $prop) { continue }
            $keyText = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
            $normalized[$keyText] = $prop.Value
        }
        return $normalized
    }

    return @{ __raw = $Value }
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
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($check in @($checksRaw)) {
        if ($null -eq $check) { continue }
        $checks.Add($check)
    }

    $evidence = Convert-ToStringArraySafe -Value (Safe-Get -Object $node -Key 'evidence' -Default @())

    return [ordered]@{
        class = $classification
        reason = $reason
        confidence = $confidence
        checks = @($checks)
        evidence = @($evidence)
    }
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
    $checks = New-Object System.Collections.Generic.List[object]

    foreach ($check in @($checksRaw)) {
        if ($null -eq $check) { continue }

        if ($check -is [System.Collections.IDictionary] -or $check -is [PSCustomObject]) {
            $checks.Add([ordered]@{
                name = [string](Safe-Get -Object $check -Key 'name' -Default 'unnamed_check')
                status = [string](Safe-Get -Object $check -Key 'status' -Default 'UNKNOWN')
                detail = [string](Safe-Get -Object $check -Key 'detail' -Default '')
            })
            continue
        }

        $checks.Add([ordered]@{
            name = 'closeout_check'
            status = 'UNKNOWN'
            detail = [string]$check
        })
    }

    $evidence = Convert-ToStringArraySafe -Value (Safe-Get -Object $node -Key 'evidence' -Default @())

    return [ordered]@{
        class = [string](Safe-Get -Object $node -Key 'class' -Default 'BLOCKED_BY_UNKNOWN')
        reason = [string](Safe-Get -Object $node -Key 'reason' -Default 'Product closeout classification was not generated.')
        confidence = [string](Safe-Get -Object $node -Key 'confidence' -Default 'low')
        checks = @($checks)
        evidence = @($evidence)
    }
}

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

    return @{
        routes = $normalizedRoutesOutput
        raw_count = $rawRouteCount
        dropped_count = $droppedCount
        warnings = $shapeWarningsOutput
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
        if ($Value -is [System.Collections.ICollection]) {
            $output = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) {
                $output.Add($item)
            }
            return [object[]]$output.ToArray()
        }
        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            $output = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) {
                $output.Add($item)
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
            if ($null -eq $dominant -or [int]$pattern.routes_affected -gt [int]$dominant.routes_affected) {
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
            $screenshotEvidence = @($baseScreenshots + $issueScreenshots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            $routeIssues = New-Object System.Collections.Generic.List[object]

            $operationLabel = 'PQ3_route_contradictions_build'
            $expression = 'Route contradiction candidate construction'
            if ($primaryVerdict -eq 'HEALTHY' -and ($thin -or $weakCta -or $deadEnd -or $bodyTextLength -lt 250 -or $statusCode -ge 400 -or [int](Safe-Get -Object $route -Key 'screenshotCount' -Default 0) -eq 0)) {
                $routeContradictions.Add([ordered]@{
                        class = 'HEALTHY_BUT_VISUALLY_WEAK'
                        scope = 'ROUTE'
                        severity = 'REVIEW'
                        evidence = "verdict=HEALTHY while thin=$thin weak_cta=$weakCta dead_end=$deadEnd bodyTextLength=$bodyTextLength status=$statusCode screenshotCount=$([int](Safe-Get -Object $route -Key 'screenshotCount' -Default 0))"
                    })
            }
            if ((-not $empty) -and $bodyTextLength -gt 120 -and ($weakCta -or $deadEnd)) {
                $routeContradictions.Add([ordered]@{
                        class = 'NON_EMPTY_BUT_LOW_VALUE'
                        scope = 'ROUTE'
                        severity = 'REVIEW'
                        evidence = "bodyTextLength=$bodyTextLength avoids EMPTY, but weak_cta=$weakCta dead_end=$deadEnd links=$links buttonCount=$buttonCount hasNav=$hasNav"
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
            foreach ($issue in @($routeIssues)) {
                $ev = Convert-ToPageQualityStringArray -Value (Safe-Get -Object $issue -Key 'evidence_refs' -Default @())
                if ($ev.Count -eq 0) { $issuesMissingEvidence++ }
            }

            if (-not $verdictCounts.ContainsKey($primaryVerdict)) {
                $verdictCounts[$primaryVerdict] = 0
            }
            $verdictCounts[$primaryVerdict] = [int]$verdictCounts[$primaryVerdict] + 1

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
                issues = @($routeIssues.ToArray())
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

function Build-ContradictionLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [string[]]$MissingInputs
    )

    $routes = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $repeatedPatternCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
    $issueRollupTotal =
        [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0) +
        [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)

    $routeCandidates = New-Object System.Collections.Generic.List[object]
    $operationLabel = 'C1_prepare_contradiction_candidates'
    $expression = 'materialize route contradiction_candidates into deterministic object[] before route candidate projection'
    $activeRoutePath = ''
    $candidateSource = $null
    $candidateSourceArray = @()
    try {
        foreach ($route in @($routes)) {
            $activeRoutePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
            $candidateSource = Safe-Get -Object $route -Key 'contradiction_candidates' -Default @()
            $candidateSourceArray = Convert-ToObjectArraySafe -Value $candidateSource
            foreach ($candidate in $candidateSourceArray) {
                $routeCandidates.Add([ordered]@{
                        class = [string](Safe-Get -Object $candidate -Key 'class' -Default 'UNKNOWN')
                        scope = 'ROUTE'
                        route_path = $activeRoutePath
                        severity = [string](Safe-Get -Object $candidate -Key 'severity' -Default 'REVIEW')
                        evidence = [string](Safe-Get -Object $candidate -Key 'evidence' -Default '')
                    })
            }
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ContradictionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $candidateSource -RightOperand $candidateSourceArray -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                operation_label = $operationLabel
                expression = $expression
                route_path_if_available = $activeRoutePath
                contradiction_candidate_source_type = if ($null -eq $candidateSource) { '<null>' } else { $candidateSource.GetType().FullName }
                local_collection_type = if ($null -eq $candidateSourceArray) { '<null>' } else { $candidateSourceArray.GetType().FullName }
                local_collection_count = [int]@($candidateSourceArray).Count
                exact_failing_sub_expression = '$routeCandidates.Add([ordered]@{...})'
                error_message = $_.Exception.Message
            })
        throw "Build-ContradictionLayer failed at [$operationLabel]: $($_.Exception.Message)"
    }

    $siteCandidates = New-Object System.Collections.Generic.List[object]

    $sourceEnabled = [bool](Safe-Get -Object $SourceLayer -Key 'enabled' -Default $false)
    $sourceFileCount = [int](Safe-Get -Object (Safe-Get -Object $SourceLayer -Key 'summary' -Default @{}) -Key 'file_count' -Default 0)
    $sourceTopDirs = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $SourceLayer -Key 'summary' -Default @{}) -Key 'top_level_directories' -Default @())
    $thinOrLowValueRoutes = Convert-ToObjectArraySafe -Value @($routes | Where-Object {
            $pageFlags = Safe-Get -Object $_ -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)
        })
    if ($sourceEnabled -and $sourceFileCount -ge 25 -and @($sourceTopDirs).Where({ $_ -ne $null }).Count -ge 2 -and @($thinOrLowValueRoutes).Where({ $_ -ne $null }).Count -gt 0) {
        $siteCandidates.Add([ordered]@{
                class = 'SOURCE_EXPECTS_MORE_THAN_LIVE_DELIVERS'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "source inventory suggests non-trivial implementation (file_count=$sourceFileCount, top_dirs=$(@($sourceTopDirs).Where({ $_ -ne $null }).Count)) while low-value live routes exist ($(@($thinOrLowValueRoutes).Where({ $_ -ne $null }).Count))."
            })
    }

    if ($repeatedPatternCount -gt 0 -and $issueRollupTotal -ge 2) {
        $siteCandidates.Add([ordered]@{
                class = 'SUMMARY_UNDERSTATES_PATTERN'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "repeated_pattern_count=$repeatedPatternCount with aggregate issue observations=$issueRollupTotal can make top-line summary sound milder than route-level evidence."
            })
    }

    $degradedState = ($pageQualityStatus -in @('PARTIAL', 'NOT_EVALUATED')) -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0
    $evidenceRich = (@($routes).Where({ $_ -ne $null }).Count -ge 3) -and (@($routeCandidates).Where({ $_ -ne $null }).Count -ge 2)
    if ($degradedState -and $evidenceRich) {
        $siteCandidates.Add([ordered]@{
                class = 'PARTIAL_BUT_EVIDENCE_RICH'
                scope = 'SITE'
                severity = 'REVIEW'
                evidence = "run degradation detected (page_quality_status=$pageQualityStatus, missing_inputs=$(@($MissingInputs).Where({ $_ -ne $null }).Count)) but route-level contradiction evidence is still meaningful (routes=$(@($routes).Where({ $_ -ne $null }).Count), route_candidates=$(@($routeCandidates).Where({ $_ -ne $null }).Count))."
            })
    }

    $operationLabel = 'C2_combine_contradiction_candidates'
    $expression = 'explicit object[] materialization + local object[] combine container (no implicit list arithmetic)'
    $routeCandidateArray = @()
    $siteCandidateArray = @()
    $allCandidates = @()
    $classCounts = @{}
    $combineExpression = '$combinedCandidates += $routeCandidateArray; $combinedCandidates += $siteCandidateArray'

    try {
        $routeCandidateArray = [object[]](Convert-ToObjectArraySafe -Value $routeCandidates)
        $siteCandidateArray = [object[]](Convert-ToObjectArraySafe -Value $siteCandidates)

        $combinedCandidates = New-Object System.Collections.ArrayList
        foreach ($candidate in $routeCandidateArray) {
            [void]$combinedCandidates.Add($candidate)
        }
        foreach ($candidate in $siteCandidateArray) {
            [void]$combinedCandidates.Add($candidate)
        }
        $allCandidates = [object[]]$combinedCandidates.ToArray([object])

        $operationLabel = 'C3_build_contradiction_class_counts'
        foreach ($candidate in $allCandidates) {
            $className = [string](Safe-Get -Object $candidate -Key 'class' -Default 'UNKNOWN')
            if (-not $classCounts.ContainsKey($className)) {
                $classCounts[$className] = 0
            }
            $classCounts[$className] = [int]$classCounts[$className] + 1
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ContradictionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $operationLabel -ActiveExpression $expression -LeftOperand $routeCandidateArray -RightOperand $siteCandidateArray -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                operation_label = $operationLabel
                expression = $expression
                route_candidates_type = if ($null -eq $routeCandidates) { '<null>' } else { $routeCandidates.GetType().FullName }
                site_candidates_type = if ($null -eq $siteCandidates) { '<null>' } else { $siteCandidates.GetType().FullName }
                route_candidate_array_type = if ($null -eq $routeCandidateArray) { '<null>' } else { $routeCandidateArray.GetType().FullName }
                site_candidate_array_type = if ($null -eq $siteCandidateArray) { '<null>' } else { $siteCandidateArray.GetType().FullName }
                exact_combine_expression = $combineExpression
                route_candidate_count = [int]@($routeCandidateArray).Count
                site_candidate_count = [int]@($siteCandidateArray).Count
                error_message = $_.Exception.Message
            })
        throw "Build-ContradictionLayer failed at [$operationLabel]: $($_.Exception.Message)"
    }

    return @{
        route_candidates = @($routeCandidateArray)
        site_candidates = @($siteCandidateArray)
        candidates = @($allCandidates)
        class_counts = $classCounts
        total_candidates = [int](@($allCandidates) | Where-Object { $_ -ne $null }).Count
        route_candidate_count = [int](@($routeCandidateArray) | Where-Object { $_ -ne $null }).Count
        site_candidate_count = [int](@($siteCandidateArray) | Where-Object { $_ -ne $null }).Count
    }
}

function Build-SiteDiagnosisLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [string[]]$MissingInputs
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $routeDetails = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $patternSummary = Safe-Get -Object $liveSummary -Key 'site_pattern_summary' -Default @{}
    $dominantPattern = Safe-Get -Object $patternSummary -Key 'dominant_pattern' -Default $null
    $dominantPatternLabel = [string](Safe-Get -Object $dominantPattern -Key 'label' -Default '')
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')

    $totalRoutes = [int]@($routeDetails).Count
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
    $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $repeatedPatternCount = [int](Safe-Get -Object $patternSummary -Key 'repeated_pattern_count' -Default 0)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $conversionWeakRoutes = [int]($weakCtaRoutes + $deadEndRoutes)
    $thinOrEmptyRoutes = [int]($emptyRoutes + $thinRoutes)
    $nonEmptyRoutes = if ($totalRoutes -gt $emptyRoutes) { [int]($totalRoutes - $emptyRoutes) } else { 0 }

    $siteClass = 'PARTIAL_PRODUCT_SYSTEM'
    $reason = 'Site has partially working evidence but quality is uneven across route signals.'
    $evidence = New-Object System.Collections.Generic.List[string]

    if (-not $LiveLayer.enabled -or -not $LiveLayer.ok -or $totalRoutes -eq 0 -or $pageQualityStatus -eq 'NOT_EVALUATED') {
        $siteClass = 'BROKEN_SYSTEM'
        $reason = 'Live system evidence is missing or degraded, so the audited site behavior is not reliably operational.'
    }
    elseif ($contaminatedRoutes -ge 2 -or ($totalRoutes -gt 0 -and ($contaminatedRoutes * 2) -ge $totalRoutes -and $contaminatedRoutes -ge 1)) {
        $siteClass = 'TRUST_CONTAMINATED_SYSTEM'
        $reason = 'Trust contamination repeats across meaningful routes, weakening core credibility signals.'
    }
    elseif ($totalRoutes -gt 0 -and $thinOrEmptyRoutes -ge [Math]::Ceiling($totalRoutes * 0.60) -and $conversionWeakRoutes -ge 1) {
        $siteClass = 'CONTENT_SHELL'
        $reason = 'Most sampled routes are empty/thin and conversion flow is weak, indicating shell-like site behavior.'
    }
    elseif ($totalRoutes -gt 0 -and $emptyRoutes -eq 0 -and $thinRoutes -ge [Math]::Ceiling($totalRoutes * 0.50)) {
        $siteClass = 'STRUCTURALLY_PRESENT_BUT_THIN'
        $reason = 'Routes are present but content depth is repeatedly thin across the sample.'
    }
    elseif ($nonEmptyRoutes -ge 2 -and $conversionWeakRoutes -ge [Math]::Max(2, [Math]::Ceiling($totalRoutes * 0.50))) {
        $siteClass = 'WEAK_CONVERSION_SYSTEM'
        $reason = 'Routes are mostly non-empty but conversion and onward decision paths are consistently weak.'
    }
    elseif ($pageQualityStatus -eq 'EVALUATED' -and $thinOrEmptyRoutes -eq 0 -and $conversionWeakRoutes -eq 0 -and $contaminatedRoutes -eq 0 -and $contradictionTotal -eq 0) {
        $siteClass = 'DECISION_CAPABLE_SYSTEM'
        $reason = 'Route quality and trust signals are consistently healthy with no deterministic contradiction alerts.'
    }
    elseif ($pageQualityStatus -eq 'EVALUATED' -and $emptyRoutes -eq 0 -and $contaminatedRoutes -eq 0 -and $conversionWeakRoutes -le 1 -and $thinRoutes -le 1) {
        $siteClass = 'HEALTHY_BUT_EARLY'
        $reason = 'Core signals are mostly healthy with only light early-stage quality gaps.'
    }
    elseif ($conversionWeakRoutes -ge 1 -and $thinOrEmptyRoutes -le [Math]::Max(1, [Math]::Floor($totalRoutes * 0.34))) {
        $siteClass = 'WEAK_DECISION_SYSTEM'
        $reason = 'Decision-path weakness is the dominant issue while baseline content structure is mostly present.'
    }

    $evidence.Add("route_count=$totalRoutes empty=$emptyRoutes thin=$thinRoutes weak_cta=$weakCtaRoutes dead_end=$deadEndRoutes contaminated=$contaminatedRoutes")
    $evidence.Add("page_quality_status=$pageQualityStatus repeated_pattern_count=$repeatedPatternCount contradiction_candidates=$contradictionTotal")
    if (-not [string]::IsNullOrWhiteSpace($dominantPatternLabel)) {
        $evidence.Add("dominant_pattern=$dominantPatternLabel")
    }
    if (@($MissingInputs).Where({ $_ -ne $null }).Count -gt 0) {
        $evidence.Add("missing_inputs=$(@($MissingInputs).Where({ $_ -ne $null }).Count)")
    }

    $confidence = 'HIGH'
    $degradedRun = ($pageQualityStatus -in @('PARTIAL', 'NOT_EVALUATED')) -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0 -or (-not $LiveLayer.ok)
    if ($degradedRun -or $totalRoutes -lt 3) {
        $confidence = 'MEDIUM'
    }
    if ($pageQualityStatus -eq 'NOT_EVALUATED' -or $totalRoutes -eq 0 -or @($MissingInputs).Where({ $_ -ne $null }).Count -gt 0 -or (-not $LiveLayer.ok)) {
        $confidence = 'LOW'
    }
    elseif ($confidence -eq 'HIGH' -and $contradictionTotal -ge 3) {
        $confidence = 'MEDIUM'
    }
    elseif ($confidence -eq 'MEDIUM' -and $contradictionTotal -ge 4) {
        $confidence = 'LOW'
    }

    return @{
        class = $siteClass
        reason = $reason
        evidence = @($evidence | Select-Object -First 4)
        confidence = $confidence
    }
}

function Build-MaturityReadinessLayer {
    param(
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$SiteDiagnosis,
        [hashtable]$ContradictionSummary,
        [string[]]$MissingInputs
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $totalRoutes = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $conversionWeak = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0) + [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $evidenceCoverage = Safe-Get -Object $liveSummary -Key 'evidence_coverage' -Default @{}
    $evidenceRichness = [string](Safe-Get -Object $evidenceCoverage -Key 'evidence_richness' -Default 'SPARSE')
    $missingCount = (@($MissingInputs) | Where-Object { $_ -ne $null }).Count

    $class = 'NOT_READY'
    $reason = 'Run or route-quality evidence is insufficient for release review.'

    if ($missingCount -gt 0 -or -not $LiveLayer.enabled -or $pageQualityStatus -eq 'NOT_EVALUATED' -or $totalRoutes -eq 0) {
        $class = 'NOT_READY'
        $reason = 'Critical runtime evidence is missing or page-quality evaluation did not complete.'
    }
    elseif ($diagnosisClass -in @('BROKEN_SYSTEM', 'CONTENT_SHELL', 'TRUST_CONTAMINATED_SYSTEM')) {
        $class = 'EARLY_STRUCTURE_ONLY'
        $reason = 'System structure is present but deterministic quality/trust blockers dominate.'
    }
    elseif ($emptyRoutes -gt 0 -or $contaminatedRoutes -gt 0) {
        $class = 'PARTIALLY_USABLE'
        $reason = 'Some routes are usable, but empty or trust-contaminated routes block broad reliability.'
    }
    elseif ($thinRoutes -ge 1 -or $conversionWeak -ge 2 -or $evidenceRichness -eq 'SPARSE') {
        $class = 'USABLE_BUT_WEAK'
        $reason = 'Core routes are functioning, but quality depth/conversion coverage remains weak.'
    }
    elseif ($contradictionTotal -ge 3) {
        $class = 'ANALYST_REVIEW_REQUIRED'
        $reason = 'Contradiction density is high enough that analyst verification is required before release review.'
    }
    else {
        $class = 'RELEASE_REVIEW_READY'
        $reason = 'Deterministic route-quality, contradiction, and evidence-coverage checks are consistently healthy.'
    }

    $confidence = 'HIGH'
    if ($evidenceRichness -eq 'SPARSE' -or $totalRoutes -lt 3 -or $pageQualityStatus -eq 'PARTIAL') {
        $confidence = 'MEDIUM'
    }
    if ($pageQualityStatus -eq 'NOT_EVALUATED' -or $missingCount -gt 0 -or -not $LiveLayer.ok) {
        $confidence = 'LOW'
    }

    $evidence = @(
        "page_quality_status=$pageQualityStatus total_routes=$totalRoutes evidence_richness=$evidenceRichness",
        "empty_routes=$emptyRoutes thin_routes=$thinRoutes conversion_weak_routes=$conversionWeak contaminated_routes=$contaminatedRoutes",
        "site_diagnosis=$diagnosisClass contradiction_candidates=$contradictionTotal",
        "missing_inputs=$missingCount"
    )

    return @{
        class = $class
        reason = $reason
        evidence = @($evidence)
        confidence = $confidence
    }
}

function Build-AuditorBaselineCertification {
    param(
        [string]$FinalStatus,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [hashtable]$SiteDiagnosis,
        [hashtable]$MaturityReadiness
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'none')
    $evidenceCoverage = Safe-Get -Object $liveSummary -Key 'evidence_coverage' -Default @{}
    $evidenceRichness = [string](Safe-Get -Object $evidenceCoverage -Key 'evidence_richness' -Default 'SPARSE')
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $siteDiagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $maturityClass = [string](Safe-Get -Object $MaturityReadiness -Key 'class' -Default 'NOT_READY')

    $checks = [ordered]@{
        runtime_path_health = if ($FinalStatus -ne 'FAIL') { 'PASS' } else { 'FAIL' }
        repo_binding_truth = if (-not $SourceLayer.required -or [bool]$SourceLayer.ok) { 'PASS' } else { 'FAIL' }
        visual_evidence_truth = if ([bool]$LiveLayer.enabled -and [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0) -gt 0) { 'PASS' } else { 'FAIL' }
        page_quality_evaluation_truth = if ($pageQualityStatus -in @('EVALUATED', 'PARTIAL')) { 'PASS' } else { 'FAIL' }
        contradiction_layer_truth = if ($null -ne $ContradictionSummary) { 'PASS' } else { 'FAIL' }
        diagnosis_layer_truth = if ($siteDiagnosisClass -ne 'UNKNOWN') { 'PASS' } else { 'FAIL' }
        maturity_layer_truth = if ($maturityClass -ne 'NOT_READY' -or $pageQualityStatus -ne 'NOT_EVALUATED') { 'PASS' } else { 'FAIL' }
        operator_output_usefulness = if ($FinalStatus -ne 'FAIL' -or [bool]$LiveLayer.enabled) { 'PASS' } else { 'FAIL' }
        analyst_brief_usefulness = if ($FinalStatus -ne 'FAIL' -or [bool]$LiveLayer.enabled) { 'PASS' } else { 'FAIL' }
        bundle_report_consistency = if ($FinalStatus -in @('PASS', 'PARTIAL', 'FAIL')) { 'PASS' } else { 'FAIL' }
    }

    $failedChecks = @($checks.Keys | Where-Object { [string]$checks[$_] -eq 'FAIL' })
    $classification = 'BASELINE_READY'
    if (@($failedChecks).Where({ $_ -ne $null }).Count -gt 0) {
        $classification = "BLOCKED_BY_$($failedChecks[0].ToUpperInvariant())"
    }

    $evidence = @(
        "final_status=$FinalStatus page_quality_status=$pageQualityStatus failure_stage=$failureStage",
        "source_ok=$([bool]$SourceLayer.ok) live_enabled=$([bool]$LiveLayer.enabled) live_ok=$([bool]$LiveLayer.ok)",
        "evidence_richness=$evidenceRichness contradiction_candidates=$contradictionTotal",
        "site_diagnosis=$siteDiagnosisClass maturity=$maturityClass"
    )

    return @{
        class = $classification
        reason = if ($classification -eq 'BASELINE_READY') { 'All baseline gate checks passed for deterministic runtime and reporting layers.' } else { "Baseline gate blocked by $($failedChecks[0])." }
        confidence = if ($FinalStatus -eq 'PASS') { 'HIGH' } elseif ($FinalStatus -eq 'PARTIAL') { 'MEDIUM' } else { 'LOW' }
        checks = $checks
        evidence = @($evidence)
    }
}

function Build-PrimaryRemediationPackage {
    param(
        [hashtable]$LiveLayer,
        [hashtable]$SiteDiagnosis,
        [hashtable]$ContradictionSummary
    )

    $liveSummary = Safe-Get -Object $LiveLayer -Key 'summary' -Default @{}
    $routeDetails = Convert-ToObjectArraySafe -Value (Safe-Get -Object $LiveLayer -Key 'route_details' -Default @())
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
    $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $conversionWeakRoutes = [int]($weakCtaRoutes + $deadEndRoutes)
    $contradictionTotal = [int](Safe-Get -Object $ContradictionSummary -Key 'total_candidates' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $SiteDiagnosis -Key 'class' -Default 'UNKNOWN')

    $packageName = 'MIXED_RECOVERY_PACKAGE'
    $packageGoal = 'Stabilize route quality and eliminate the highest repeated blocker cluster first.'
    $whyFirst = 'No single blocker dominates; start with the largest repeated quality cluster to reduce multi-route risk quickly.'
    $successCheck = 'Re-run SITE_AUDITOR and confirm lower empty/thin/contamination counts plus PAGE QUALITY STATUS=EVALUATED.'
    $targetSelector = { param([object]$route) $true }

    if ($pageQualityStatus -eq 'NOT_EVALUATED') {
        $packageName = 'CORE_ROUTE_RECOVERY_PACKAGE'
        $packageGoal = 'Restore complete route evidence generation so page-quality evaluation can run deterministically.'
        $whyFirst = 'Without evaluated route quality, downstream diagnosis and remediation prioritization remain unreliable.'
        $successCheck = 'PAGE QUALITY STATUS becomes EVALUATED and no route normalization/output-writing failure stage remains.'
        $targetSelector = {
            param([object]$route)
            $status = [int](Safe-Get -Object $route -Key 'status' -Default 0)
            ($status -eq 0 -or $status -ge 400)
        }
    }
    elseif ($contaminatedRoutes -ge [Math]::Max(2, [Math]::Max($conversionWeakRoutes, ($emptyRoutes + $thinRoutes)))) {
        $packageName = 'TRUST_CLEANUP_PACKAGE'
        $packageGoal = 'Remove repeated trust-contamination markers before conversion or optimization work.'
        $whyFirst = 'Trust contamination undermines every route narrative and can invalidate otherwise acceptable conversion signals.'
        $successCheck = 'contaminated_routes drops to 0 and contradiction classes tied to contamination are reduced.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)
        }
    }
    elseif (($emptyRoutes + $thinRoutes) -ge [Math]::Max(2, $conversionWeakRoutes)) {
        $packageName = 'CORE_ROUTE_RECOVERY_PACKAGE'
        $packageGoal = 'Recover empty/thin core routes before tuning secondary conversion details.'
        $whyFirst = 'Route quality recovery restores baseline utility and prevents optimization work on non-viable pages.'
        $successCheck = 'empty_routes=0 and thin_routes reduced to <=1 on the next run.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)
        }
    }
    elseif ($conversionWeakRoutes -ge 2 -or $diagnosisClass -in @('WEAK_DECISION_SYSTEM', 'WEAK_CONVERSION_SYSTEM')) {
        $packageName = 'CONVERSION_RECOVERY_PACKAGE'
        $packageGoal = 'Repair weak CTA and dead-end navigation paths on high-intent routes.'
        $whyFirst = 'Conversion-path failure blocks practical outcomes even when pages appear content-complete.'
        $successCheck = 'weak_cta_routes + dead_end_routes drops below 2 with no repeated conversion weak pattern.'
        $targetSelector = {
            param([object]$route)
            $pageFlags = Safe-Get -Object $route -Key 'page_flags' -Default @{}
            [bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false) -or
            [bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)
        }
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($route in @($routeDetails)) {
        $path = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (& $targetSelector $route) {
            $targets.Add($path)
        }
    }
    $targetsArray = @($targets) | Where-Object { $_ -ne $null }
    if (@($targetsArray).Where({ $_ -ne $null }).Count -eq 0) {
        foreach ($route in @($routeDetails | Select-Object -First 3)) {
            $path = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $targets.Add($path)
            }
        }
    }

    $reasonEvidence = @(
        "page_quality_status=$pageQualityStatus empty=$emptyRoutes thin=$thinRoutes weak_cta=$weakCtaRoutes dead_end=$deadEndRoutes contaminated=$contaminatedRoutes contradiction_candidates=$contradictionTotal",
        "site_diagnosis=$diagnosisClass"
    )

    return @{
        package_name = $packageName
        package_goal = $packageGoal
        primary_targets = @($targets | Select-Object -Unique | Select-Object -First 5)
        why_first = $whyFirst
        success_check = $successCheck
        evidence = @($reasonEvidence)
    }
}

function Build-ProductCloseoutClassification {
    param(
        [string]$FinalStatus,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [hashtable]$ContradictionSummary,
        [hashtable]$SiteDiagnosis,
        [hashtable]$MaturityReadiness,
        [hashtable]$RemediationPackage
    )

    $activeOperationLabel = 'initialize'
    $activeExpression = ''

    try {
        $activeOperationLabel = 'normalize/source_layer'
        $activeExpression = 'Convert-ToHashtableSafe -Value $SourceLayer'
        $normalizedSourceLayer = Convert-ToHashtableSafe -Value $SourceLayer
        $activeOperationLabel = 'normalize/live_layer'
        $activeExpression = 'Convert-ToHashtableSafe -Value $LiveLayer'
        $normalizedLiveLayer = Convert-ToHashtableSafe -Value $LiveLayer
        $activeOperationLabel = 'normalize/contradiction_summary'
        $activeExpression = 'Convert-ToHashtableSafe -Value $ContradictionSummary'
        $normalizedContradictionSummary = Convert-ToHashtableSafe -Value $ContradictionSummary
        $activeOperationLabel = 'normalize/site_diagnosis'
        $activeExpression = 'Convert-ToHashtableSafe -Value $SiteDiagnosis'
        $normalizedSiteDiagnosis = Convert-ToHashtableSafe -Value $SiteDiagnosis
        $activeOperationLabel = 'normalize/maturity_readiness'
        $activeExpression = 'Convert-ToHashtableSafe -Value $MaturityReadiness'
        $normalizedMaturityReadiness = Convert-ToHashtableSafe -Value $MaturityReadiness
        $activeOperationLabel = 'normalize/remediation_package'
        $activeExpression = 'Convert-ToHashtableSafe -Value $RemediationPackage'
        $normalizedRemediationPackage = Convert-ToHashtableSafe -Value $RemediationPackage

    $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'summary' -Default @{})
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default 'none')
    $routeCount = [int](Safe-Get -Object $liveSummary -Key 'total_routes' -Default 0)
    $screenshotCount = [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0)
    $diagnosisClass = [string](Safe-Get -Object $normalizedSiteDiagnosis -Key 'class' -Default 'UNKNOWN')
    $maturityClass = [string](Safe-Get -Object $normalizedMaturityReadiness -Key 'class' -Default 'NOT_READY')

    $classCounts = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedContradictionSummary -Key 'class_counts' -Default @{})
    $totalCandidatesRaw = Safe-Get -Object $normalizedContradictionSummary -Key 'total_candidates' -Default $null
    $hasTotalCandidates = $null -ne $totalCandidatesRaw
    $contradictionHasCoreShape = ($classCounts.Count -ge 0) -and $hasTotalCandidates

    $packageName = [string](Safe-Get -Object $normalizedRemediationPackage -Key 'package_name' -Default '')
    $packageTargets = Convert-ToStringArraySafe -Value (Safe-Get -Object $normalizedRemediationPackage -Key 'primary_targets' -Default @())
    $packageTargetsArray = @($packageTargets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $packageTargetCount = @($packageTargetsArray).Count

    $checksByName = [ordered]@{
        runtime_stability = if ($FinalStatus -ne 'FAIL' -and $failureStage -in @('none', '')) { 'PASS' } else { 'FAIL' }
        source_live_evidence_integrity = if ([bool](Safe-Get -Object $normalizedLiveLayer -Key 'enabled' -Default $false) -and [bool](Safe-Get -Object $normalizedLiveLayer -Key 'ok' -Default $false) -and $routeCount -gt 0 -and $screenshotCount -gt 0 -and (-not [bool](Safe-Get -Object $normalizedSourceLayer -Key 'required' -Default $false) -or [bool](Safe-Get -Object $normalizedSourceLayer -Key 'ok' -Default $false))) { 'PASS' } else { 'FAIL' }
        page_quality_usefulness = if ($pageQualityStatus -eq 'EVALUATED') { 'PASS' } else { 'FAIL' }
        contradiction_usefulness = if ($contradictionHasCoreShape) { 'PASS' } else { 'FAIL' }
        diagnosis_usefulness = if ($diagnosisClass -ne 'UNKNOWN') { 'PASS' } else { 'FAIL' }
        maturity_usefulness = if ($maturityClass -ne 'NOT_READY') { 'PASS' } else { 'FAIL' }
        operator_output_usefulness = if (-not [string]::IsNullOrWhiteSpace([string](Safe-Get -Object $normalizedRemediationPackage -Key 'why_first' -Default ''))) { 'PASS' } else { 'FAIL' }
        remediation_package_usefulness = if (-not [string]::IsNullOrWhiteSpace($packageName) -and $packageTargetCount -gt 0) { 'PASS' } else { 'FAIL' }
        analyst_brief_usefulness = if ($pageQualityStatus -in @('EVALUATED', 'PARTIAL') -and $routeCount -gt 0) { 'PASS' } else { 'FAIL' }
        report_bundle_consistency = if ($FinalStatus -in @('PASS', 'PARTIAL', 'FAIL')) { 'PASS' } else { 'FAIL' }
    }

    $failureMap = [ordered]@{
        runtime_stability = 'RUNTIME_STABILITY'
        source_live_evidence_integrity = 'SOURCE_LIVE_EVIDENCE_INTEGRITY'
        page_quality_usefulness = 'PAGE_QUALITY_USEFULNESS'
        contradiction_usefulness = 'CONTRADICTION_USEFULNESS'
        diagnosis_usefulness = 'DIAGNOSIS_USEFULNESS'
        maturity_usefulness = 'MATURITY_USEFULNESS'
        operator_output_usefulness = 'OPERATOR_OUTPUT_USEFULNESS'
        remediation_package_usefulness = 'REMEDIATION_PACKAGE_USEFULNESS'
        analyst_brief_usefulness = 'ANALYST_BRIEF_USEFULNESS'
        report_bundle_consistency = 'REPORT_BUNDLE_CONSISTENCY'
    }

    $failedKey = ''
    foreach ($key in @($checksByName.Keys)) {
        if ([string]$checksByName[$key] -eq 'FAIL') {
            $failedKey = [string]$key
            break
        }
    }

    $classification = 'PRODUCT_READY_BASELINE'
    if (-not [string]::IsNullOrWhiteSpace($failedKey)) {
        $classification = "BLOCKED_BY_$([string]$failureMap[$failedKey])"
    }

    $confidence = 'medium'
    if ($classification -eq 'PRODUCT_READY_BASELINE' -and $FinalStatus -eq 'PASS' -and $pageQualityStatus -eq 'EVALUATED') {
        $confidence = 'high'
    }
    elseif ($FinalStatus -eq 'FAIL' -or $pageQualityStatus -in @('NOT_EVALUATED', 'PARTIAL') -or $diagnosisClass -eq 'UNKNOWN') {
        $confidence = 'low'
    }

        $activeOperationLabel = 'list/materialize/checks_enumerator'
        $activeExpression = '@($checksByName.GetEnumerator())'
        $checksEntries = @($checksByName.GetEnumerator())

        $activeOperationLabel = 'list/create/checks'
        $activeExpression = 'New-Object System.Collections.Generic.List[object]'
        $checks = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($checksEntries)) {
            $checkItem = [ordered]@{
                name = [string]$entry.Key
                status = [string]$entry.Value
            }
            $activeOperationLabel = 'list/add/checks_item'
            $activeExpression = '$checks.Add($checkItem)'
            $checks.Add($checkItem)
        }

    $reasonText = 'Deterministic closeout checks passed for baseline operator use.'
    if (-not [string]::IsNullOrWhiteSpace($failedKey)) {
        $reasonText = "Product closeout blocked by $failedKey."
    }

    $evidence = Convert-ToStringArraySafe -Value @(
        [string]"final_status=$FinalStatus failure_stage=$failureStage page_quality_status=$pageQualityStatus",
        [string]"route_count=$routeCount screenshot_count=$screenshotCount package_name=$packageName package_targets=$packageTargetCount",
        [string]"site_diagnosis=$diagnosisClass maturity=$maturityClass contradiction_shape=$contradictionHasCoreShape"
    )

        $activeOperationLabel = 'assemble/final_closeout_object'
        $activeExpression = '@{ class=...; reason=...; confidence=...; checks=...; evidence=... }'
        return @{
            class = [string]$classification
            reason = [string]$reasonText
            confidence = [string]$confidence
            checks = @($checks)
            evidence = @($evidence)
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Build-ProductCloseoutClassification' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $activeOperationLabel -ActiveExpression $activeExpression -LeftOperand $FinalStatus -RightOperand $normalizedRemediationPackage -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
            error_message = [string]$_.Exception.Message
            failure_kind = 'product_closeout_classification_instrumented_boundary'
        })
        throw
    }
}

function Convert-ToProductStatus {
    param(
        [hashtable]$Decision,
        [string]$FinalStatus
    )

    $activeOperationLabel = 'initialize'
    $activeExpression = ''

    try {
        $activeOperationLabel = 'normalize/decision'
        $activeExpression = 'Convert-ToHashtableSafe -Value $Decision'
        $normalizedInput = Convert-ToHashtableSafe -Value $Decision
        $activeOperationLabel = 'normalize/raw_closeout'
        $activeExpression = 'Safe-Get -Object $normalizedInput -Key product_closeout'
        $rawCloseout = Safe-Get -Object $normalizedInput -Key 'product_closeout' -Default $null
        if ($null -eq $rawCloseout) {
            $rawCloseout = $normalizedInput
        }

        $activeOperationLabel = 'normalize/closeout_shape'
        $activeExpression = 'Convert-ToHashtableSafe -Value (Normalize-ProductCloseout -Value $rawCloseout)'
        $normalizedCloseout = Convert-ToHashtableSafe -Value (Normalize-ProductCloseout -Value $rawCloseout)
        $activeOperationLabel = 'cast/string_fields'
        $activeExpression = 'class/reason/confidence string extraction'
        $closeoutClass = [string](Safe-Get -Object $normalizedCloseout -Key 'class' -Default 'BLOCKED_BY_UNKNOWN')
        $reason = [string](Safe-Get -Object $normalizedCloseout -Key 'reason' -Default 'Product closeout classification was not generated.')
        $confidence = [string](Safe-Get -Object $normalizedCloseout -Key 'confidence' -Default 'low')

        if ($confidence -notin @('high', 'medium', 'low')) { $confidence = 'low' }

        $status = 'FAIL'
        if ($closeoutClass -eq 'PRODUCT_READY_BASELINE') {
            $status = 'SUCCESS'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($reason)) {
            $status = 'NEEDS_FIX'
        }

        $activeOperationLabel = 'assemble/final_product_status'
        $activeExpression = '[ordered]@{ status=... }'
        return [ordered]@{
            status = [string]$status
            reason = [string]$reason
            confidence = [string]$confidence
            source_closeout_class = [string]$closeoutClass
            run_status = [string]$FinalStatus
        }
    }
    catch {
        Set-DecisionForensics -FunctionName 'Convert-ToProductStatus' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel $activeOperationLabel -ActiveExpression $activeExpression -LeftOperand $Decision -RightOperand $FinalStatus -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
            error_message = [string]$_.Exception.Message
            failure_kind = 'product_status_conversion_instrumented_boundary'
        })
        throw
    }
}


function Get-DecisionRepairHint {
    param(
        [string]$Stage,
        [string]$CoreProblem,
        [object[]]$PriorityRoutes,
        [string]$ResolvedMode,
        [string[]]$MissingInputs,
        [hashtable]$LiveSummary
    )

    $normalizedStage = [string]$Stage
    if ([string]::IsNullOrWhiteSpace($normalizedStage)) { $normalizedStage = 'BROKEN' }

    $brokenBlock = switch ($normalizedStage) {
        'BROKEN' { 'INPUT_VALIDATION_OR_LIVE_AUDIT' }
        'STRUCTURE' { 'ROUTE_STRUCTURE_AND_EMPTY_SHELLS' }
        'CONTENT' { 'ROUTE_CONTENT_DEPTH' }
        'UX' { 'VISUAL_TRUST_AND_RENDERING' }
        'CONVERSION' { 'CTA_AND_ONWARD_NAVIGATION' }
        default { 'REGRESSION_MONITORING' }
    }

    $nextAction = switch ($normalizedStage) {
        'BROKEN' { 'Fix missing inputs or failed runtime node, then rerun the same mode.' }
        'STRUCTURE' { 'Repair empty/broken routes first, then rerun to confirm structure is stable.' }
        'CONTENT' { 'Expand thin routes with primary content before polishing other layers.' }
        'UX' { 'Remove contamination/render defects visible in screenshots, then rerun.' }
        'CONVERSION' { 'Add clear CTAs and onward navigation on weak routes, then rerun.' }
        default { 'Keep monitoring and rerun after major site changes.' }
    }

    $failureStage = [string](Safe-Get -Object $LiveSummary -Key 'failure_stage' -Default '')
    if ([string]::IsNullOrWhiteSpace($failureStage)) { $failureStage = $normalizedStage }

    return [ordered]@{
        target_file = 'agents/gh_batch/site_auditor_cloud/agent.ps1'
        broken_block = $brokenBlock
        reason = [string]$CoreProblem
        next_action = $nextAction
        failed_stage = $failureStage
        mode = [string]$ResolvedMode
        missing_inputs = @(Convert-ToStringArraySafe -Value $MissingInputs)
        priority_routes = @(Convert-ToStringArraySafe -Value $PriorityRoutes | Select-Object -First 5)
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
                priority_routes = @($priorityRoutes | Select-Object -First 5)
            }
            output = [ordered]@{
                expected_change = if ($FinalStatus -eq 'PASS') { 'No patch required.' } else { 'Updated target block and a new rerun artifact set with lower severity or PASS.' }
                validation = if ($FinalStatus -eq 'PASS') { 'Maintain PASS state.' } else { 'Workflow rerun must remove or downgrade the current failed node.' }
                fail_mode = if ($FinalStatus -eq 'PASS') { 'Regression detected on next run.' } else { 'Failed node remains unchanged after rerun.' }
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


function Build-DecisionLayer {
    param(
        [string]$ResolvedMode,
        [hashtable]$SourceLayer,
        [hashtable]$LiveLayer,
        [string[]]$MissingInputs,
        [object]$Warnings
    )

    $normalizedSourceLayer = Convert-ToHashtableSafe -Value $SourceLayer
    $normalizedLiveLayer = Convert-ToHashtableSafe -Value $LiveLayer
    $normalizedMissingInputs = Convert-ToStringArraySafe -Value $MissingInputs
    $normalizedWarnings = Convert-ToDecisionWarningStringArray -Value $Warnings

    $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'summary' -Default @{})
    $routeDetails = Convert-ToObjectArraySafe -Value (Safe-Get -Object $normalizedLiveLayer -Key 'route_details' -Default @())
    $sourceRequired = [bool](Safe-Get -Object $normalizedSourceLayer -Key 'required' -Default $false)
    $sourceOk = [bool](Safe-Get -Object $normalizedSourceLayer -Key 'ok' -Default $false)
    $liveRequired = [bool](Safe-Get -Object $normalizedLiveLayer -Key 'required' -Default $false)
    $liveOk = [bool](Safe-Get -Object $normalizedLiveLayer -Key 'ok' -Default $false)

    $totalRoutes = [int]@($routeDetails).Count
    $emptyRoutes = [int](Safe-Get -Object $liveSummary -Key 'empty_routes' -Default 0)
    $thinRoutes = [int](Safe-Get -Object $liveSummary -Key 'thin_routes' -Default 0)
    $weakCtaRoutes = [int](Safe-Get -Object $liveSummary -Key 'weak_cta_routes' -Default 0)
    $deadEndRoutes = [int](Safe-Get -Object $liveSummary -Key 'dead_end_routes' -Default 0)
    $contaminatedRoutes = [int](Safe-Get -Object $liveSummary -Key 'contaminated_routes' -Default 0)
    $screenshotCount = [int](Safe-Get -Object $liveSummary -Key 'screenshot_count' -Default 0)
    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    if ([string]::IsNullOrWhiteSpace($pageQualityStatus)) { $pageQualityStatus = 'NOT_EVALUATED' }

    $issueClassCounts = @{}
    $priorityRouteCandidates = New-Object System.Collections.Generic.List[object]
    foreach ($route in @($routeDetails)) {
        $issues = Normalize-CollectionShape -Value (Safe-Get -Object $route -Key 'issues' -Default @())
        foreach ($issue in @($issues)) {
            $issueClass = [string](Safe-Get -Object $issue -Key 'class' -Default '')
            if ([string]::IsNullOrWhiteSpace($issueClass)) { continue }
            if (-not $issueClassCounts.ContainsKey($issueClass)) { $issueClassCounts[$issueClass] = 0 }
            $issueClassCounts[$issueClass] = [int]$issueClassCounts[$issueClass] + 1
        }

        $routePath = [string](Safe-Get -Object $route -Key 'route_path' -Default '')
        if ([string]::IsNullOrWhiteSpace($routePath)) { continue }
        $pageFlags = Convert-ToHashtableSafe -Value (Safe-Get -Object $route -Key 'page_flags' -Default @{})
        $severity = 0
        if ([bool](Safe-Get -Object $pageFlags -Key 'empty' -Default $false)) { $severity += 9 }
        if ([bool](Safe-Get -Object $pageFlags -Key 'ui_contamination' -Default $false)) { $severity += 7 }
        if ([bool](Safe-Get -Object $pageFlags -Key 'thin' -Default $false)) { $severity += 5 }
        if ([bool](Safe-Get -Object $pageFlags -Key 'weak_cta' -Default $false)) { $severity += 4 }
        if ([bool](Safe-Get -Object $pageFlags -Key 'dead_end' -Default $false)) { $severity += 4 }
        $statusCode = [int](Safe-Get -Object $route -Key 'status' -Default 0)
        if ($statusCode -eq 0 -or $statusCode -ge 400) { $severity += 3 }
        if ($severity -gt 0) {
            $priorityRouteCandidates.Add([ordered]@{
                route_path = $routePath
                severity = $severity
            })
        }
    }

    $priorityRoutes = @(
        $priorityRouteCandidates |
            Sort-Object -Property @{Expression='severity';Descending=$true}, @{Expression='route_path';Descending=$false} |
            Select-Object -First 5 |
            ForEach-Object { [string]$_.route_path }
    )

    $missingInputCount = @($normalizedMissingInputs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    $conversionWeak = [int]($weakCtaRoutes + $deadEndRoutes)

    $stage = 'READY'
    if ($missingInputCount -gt 0 -or ($sourceRequired -and -not $sourceOk) -or ($liveRequired -and -not $liveOk) -or $pageQualityStatus -eq 'NOT_EVALUATED' -or ($liveRequired -and $totalRoutes -eq 0)) {
        $stage = 'BROKEN'
    }
    elseif ($emptyRoutes -gt 0 -or [int](Safe-Get -Object $issueClassCounts -Key 'DUPLICATE_SHELL_OR_MISSING_CRITICAL_BLOCK' -Default 0) -gt 0 -or [int](Safe-Get -Object $issueClassCounts -Key 'SEVERE_LAYOUT_BREAK' -Default 0) -gt 0) {
        $stage = 'STRUCTURE'
    }
    elseif ($contaminatedRoutes -gt 0 -or [int](Safe-Get -Object $issueClassCounts -Key 'OVERLAY_OR_UI_CONTAMINATION' -Default 0) -gt 0 -or [int](Safe-Get -Object $issueClassCounts -Key 'BROKEN_RENDER_OR_TEMPLATE_LEAKAGE' -Default 0) -gt 0) {
        $stage = 'UX'
    }
    elseif ($thinRoutes -gt 0) {
        $stage = 'CONTENT'
    }
    elseif ($conversionWeak -gt 0) {
        $stage = 'CONVERSION'
    }

    $coreProblem = switch ($stage) {
        'BROKEN' { "Audit evidence is incomplete or degraded (page_quality_status=$pageQualityStatus, routes=$totalRoutes, screenshots=$screenshotCount)." }
        'STRUCTURE' { "$emptyRoutes route(s) are empty or structurally broken, so core page delivery is unreliable." }
        'UX' { "$contaminatedRoutes route(s) show trust/render contamination that weakens credibility." }
        'CONTENT' { "$thinRoutes route(s) are structurally present but too thin to be useful." }
        'CONVERSION' { "$conversionWeak route observations show weak CTA or dead-end user flow." }
        default { 'No deterministic blocker remains across the audited route sample.' }
    }

    $p0List = New-Object System.Collections.Generic.List[string]
    foreach ($missing in @($normalizedMissingInputs)) { Add-UniqueString -List $p0List -Value "Missing required input: $missing" }
    if ($stage -eq 'BROKEN' -and $pageQualityStatus -eq 'NOT_EVALUATED') {
        Add-UniqueString -List $p0List -Value "Page-quality evaluation did not complete (status=$pageQualityStatus)."
    }
    if ($stage -eq 'STRUCTURE' -and $emptyRoutes -gt 0) {
        Add-UniqueString -List $p0List -Value "$emptyRoutes route(s) are empty or near-empty."
    }
    if ($stage -eq 'STRUCTURE' -and @($priorityRoutes).Count -gt 0) {
        Add-UniqueString -List $p0List -Value "Highest-risk structure routes: $((@($priorityRoutes) | Select-Object -First 3) -join ', ')."
    }
    if ($stage -eq 'UX' -and $contaminatedRoutes -gt 0) {
        Add-UniqueString -List $p0List -Value "$contaminatedRoutes route(s) show UI contamination or render leakage."
    }
    if ($stage -eq 'CONTENT' -and $thinRoutes -gt 0) {
        Add-UniqueString -List $p0List -Value "$thinRoutes route(s) are thin-content and underdeveloped."
    }
    if ($stage -eq 'CONVERSION' -and $conversionWeak -gt 0) {
        Add-UniqueString -List $p0List -Value "$conversionWeak route observations show weak CTA/dead-end progression."
    }
    if (@($normalizedWarnings).Count -gt 0 -and $p0List.Count -lt 5) {
        foreach ($warning in @($normalizedWarnings | Select-Object -First 3)) {
            Add-UniqueString -List $p0List -Value [string]$warning
        }
    }
    if ($p0List.Count -eq 0 -and $stage -eq 'READY') {
        Add-UniqueString -List $p0List -Value 'No deterministic blocker detected in this run.'
    }

    $nowList = New-Object System.Collections.Generic.List[string]
    $afterList = New-Object System.Collections.Generic.List[string]
    switch ($stage) {
        'BROKEN' {
            Add-UniqueString -List $nowList -Value 'Fix the missing input or failed runtime node, then rerun the same mode.'
            Add-UniqueString -List $nowList -Value 'Confirm audit_result.json and visual evidence are regenerated before trusting summaries.'
            Add-UniqueString -List $afterList -Value 'After runtime stability, classify structure/content/conversion blockers.'
        }
        'STRUCTURE' {
            Add-UniqueString -List $nowList -Value 'Repair empty or broken shell routes before any optimization work.'
            Add-UniqueString -List $nowList -Value 'Use screenshots to verify each repaired route now renders as a real page.'
            Add-UniqueString -List $afterList -Value 'After structure is fixed, expand thin content and tighten conversion paths.'
        }
        'UX' {
            Add-UniqueString -List $nowList -Value 'Remove overlays, render leakage, or contamination visible in evidence screenshots.'
            Add-UniqueString -List $afterList -Value 'After trust issues are removed, improve content depth and CTA clarity.'
        }
        'CONTENT' {
            Add-UniqueString -List $nowList -Value 'Expand thin routes with primary intent, useful body copy, and clear route purpose.'
            Add-UniqueString -List $afterList -Value 'After content depth improves, tighten CTA and onward navigation.'
        }
        'CONVERSION' {
            Add-UniqueString -List $nowList -Value 'Add clear CTA and onward navigation on weak decision routes.'
            Add-UniqueString -List $afterList -Value 'After conversion blockers are removed, tune UX polish and evidence coverage.'
        }
        default {
            Add-UniqueString -List $nowList -Value 'Keep the current baseline and rerun after major site changes.'
            Add-UniqueString -List $afterList -Value 'Use screenshots to monitor regression instead of expanding scope immediately.'
        }
    }

    $contradictionSummary = @{}
    $siteDiagnosis = @{}
    $maturityReadiness = @{}
    $auditorBaseline = @{}
    $remediationPackage = @{}
    $productCloseout = Normalize-ProductCloseout -Value @{
        class = if ($stage -eq 'READY') { 'PRODUCT_READY_BASELINE' } else { 'BLOCKED_BY_PRIMARY_ISSUE' }
        reason = $coreProblem
        confidence = if ($stage -eq 'READY') { 'high' } else { 'medium' }
        checks = @()
        evidence = @("stage=$stage")
    }

    try {
        $contradictionSummary = Build-ContradictionLayer -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -MissingInputs $normalizedMissingInputs
        $siteDiagnosis = Build-SiteDiagnosisLayer -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -MissingInputs $normalizedMissingInputs
        $maturityReadiness = Build-MaturityReadinessLayer -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary -MissingInputs $normalizedMissingInputs
        $remediationPackage = Build-PrimaryRemediationPackage -LiveLayer $normalizedLiveLayer -SiteDiagnosis $siteDiagnosis -ContradictionSummary $contradictionSummary
        $productCloseout = Build-ProductCloseoutClassification -FinalStatus (if ($stage -eq 'READY') { 'PASS' } else { 'PARTIAL' }) -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness -RemediationPackage $remediationPackage
        $auditorBaseline = Build-AuditorBaselineCertification -FinalStatus (if ($stage -eq 'READY') { 'PASS' } else { 'PARTIAL' }) -SourceLayer $normalizedSourceLayer -LiveLayer $normalizedLiveLayer -ContradictionSummary $contradictionSummary -SiteDiagnosis $siteDiagnosis -MaturityReadiness $maturityReadiness
    }
    catch {
        $helperFailure = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($helperFailure)) { $helperFailure = 'Decision helper failure.' }
        Add-UniqueString -List $afterList -Value "Decision helper degraded: $helperFailure"
        if (@($priorityRoutes).Count -gt 0) {
            Add-UniqueString -List $afterList -Value "Use screenshot-first review on: $((@($priorityRoutes) | Select-Object -First 3) -join ', ')."
        }
        if ($null -eq $global:DecisionForensics) {
            Set-DecisionForensics -FunctionName 'Build-DecisionLayer' -ActivePhase 'DECISION_BUILD' -ActiveOperationLabel 'HELPER_LAYER' -ActiveExpression 'Build-* helper chain' -LeftOperand $normalizedLiveLayer -RightOperand $normalizedSourceLayer -StackHintIfAvailable $_.ScriptStackTrace -AdditionalContext ([ordered]@{
                error_message = $helperFailure
                helper_chain = 'Build-ContradictionLayer -> Build-SiteDiagnosisLayer -> Build-MaturityReadinessLayer -> Build-PrimaryRemediationPackage -> Build-ProductCloseoutClassification'
            })
        }
    }

    $repairHint = Get-DecisionRepairHint -Stage $stage -CoreProblem $coreProblem -PriorityRoutes $priorityRoutes -ResolvedMode $ResolvedMode -MissingInputs $normalizedMissingInputs -LiveSummary $liveSummary

    $decision = [ordered]@{
        stage = [string]$stage
        core_problem = [string]$coreProblem
        inputs = @($normalizedMissingInputs)
        warnings = @($normalizedWarnings)
        p0 = @($p0List.ToArray() | Select-Object -Unique)
        p1 = @()
        p2 = @()
        problems = @($p0List.ToArray() | Select-Object -Unique)
        do_next = @($nowList.ToArray() | Select-Object -Unique)
        next_actions = @($nowList.ToArray() | Select-Object -Unique)
        do_next_now = @($nowList.ToArray() | Select-Object -Unique)
        do_next_after = @($afterList.ToArray() | Select-Object -Unique)
        do_next_detail = [ordered]@{
            now = @($nowList.ToArray() | Select-Object -Unique)
            after = @($afterList.ToArray() | Select-Object -Unique)
        }
        repair_hint = $repairHint
        priority_routes = @($priorityRoutes)
        site_diagnosis = Convert-ToHashtableSafe -Value $siteDiagnosis
        maturity_readiness = Convert-ToHashtableSafe -Value $maturityReadiness
        auditor_baseline = Convert-ToHashtableSafe -Value $auditorBaseline
        remediation_package = Convert-ToHashtableSafe -Value $remediationPackage
        product_closeout = Normalize-ProductCloseout -Value $productCloseout
        contradiction_summary = Convert-ToHashtableSafe -Value $contradictionSummary
        clean_state = if ($stage -eq 'READY') { 'CLEAN' } else { 'NOT_CLEAN' }
    }

    return $decision
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
    $limiterText = if ($confidenceLimiters.Count -gt 0) { $confidenceLimiters -join ' ' } else { 'none; enabled deterministic checks completed.' }
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

    if ($null -eq $Value) { return @() }
    return @($Value)
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

    $sourceStatus = Get-LayerStatusLabel -Layer $sourceLayer -DisabledLabel 'UNKNOWN'
    $liveStatus = Get-LayerStatusLabel -Layer $liveLayer -DisabledLabel 'UNKNOWN'

    $pageQualityStatus = [string](Safe-Get -Object $liveSummary -Key 'page_quality_status' -Default 'NOT_EVALUATED')
    if ([string]::IsNullOrWhiteSpace($pageQualityStatus)) { $pageQualityStatus = 'NOT_EVALUATED' }

    $failureStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default '')
    if ([string]::IsNullOrWhiteSpace($failureStage)) { $failureStage = [string]$CurrentStage }

    $confirmedStages = Get-TruthBackedConfirmedStages -SourceStatus $sourceStatus -LiveStatus $liveStatus -PageQualityStatus $pageQualityStatus -LastSuccessStage $LastSuccessStage -CurrentStage $CurrentStage

    $truthSources = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($AuditResultPath) -and (Test-Path $AuditResultPath -PathType Leaf)) {
        $truthSources.Add('reports/audit_result.json')
    }
    $routeTracePath = Join-Path $reportsDir 'route_normalization_trace.json'
    if (Test-Path $routeTracePath -PathType Leaf) {
        $truthSources.Add('reports/route_normalization_trace.json')
    }

    $errorMessage = [string]$FailureReason
    if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = '' }

    $blocker = [string]$FailureReason
    if ([string]::IsNullOrWhiteSpace($blocker)) { $blocker = 'Unknown fallback failure.' }

    return [ordered]@{
        source_status = $sourceStatus
        live_status = $liveStatus
        page_quality_status = $pageQualityStatus
        product_status = $productStatus
        product_reason = [string](Safe-Get -Object $productStatusDetail -Key 'reason' -Default 'Fallback report only.')
        repo_summary_status = [string](Safe-Get -Object $sourceSummary -Key 'status' -Default 'UNKNOWN')
        failure_stage = $failureStage
        error_message = $errorMessage
        failure_node = [string]$CurrentStage
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

    $sourceSummary = Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'source' -Default @{}) -Key 'summary' -Default @{}
    $repoSummaryStatus = [string](Safe-Get -Object $sourceSummary -Key 'status' -Default '')

    $failedStage = [string](Safe-Get -Object $liveSummary -Key 'failure_stage' -Default '')
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

    $primaryTruth = Convert-ToObjectArrayOrEmpty -Value @($artifactItems | Where-Object { $_.priority_for_operator -eq 'high' } | ForEach-Object { $_.path })
    $usablePartialArtifacts = ($artifactItems.Count -gt 0)

    $confirmedPassingStages = New-Object System.Collections.Generic.List[string]
    if ($sourceStatus -eq 'PASS') { $confirmedPassingStages.Add('SOURCE_AUDIT') }
    if ($liveStatus -eq 'PASS') { $confirmedPassingStages.Add('LIVE_AUDIT') }
    if ($pageQualityStatus -notin @('NOT_EVALUATED', 'PARTIAL')) { $confirmedPassingStages.Add('PAGE_QUALITY_BUILD') }
    if ($FinalStatus -eq 'PASS') { $confirmedPassingStages.Add('OPERATOR_OUTPUT_CONTRACT') }

    $decisionBuildFailedNode = ''
    if ($null -ne $global:DecisionForensics) {
        $dfFunction = [string](Safe-Get -Object $global:DecisionForensics -Key 'function_name' -Default '')
        $dfOperation = [string](Safe-Get -Object $global:DecisionForensics -Key 'activeOperationLabel' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($dfFunction) -or -not [string]::IsNullOrWhiteSpace($dfOperation)) {
            $decisionBuildFailedNode = "DECISION_BUILD/$dfFunction/$dfOperation".TrimEnd('/')
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

    $repoSummaryOut = [string]$repoSummaryStatus
    if ([string]::IsNullOrWhiteSpace($repoSummaryOut)) { $repoSummaryOut = 'UNKNOWN' }

    $errorMessage = [string]$FailureReason
    if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = '' }

    $evidence = [ordered]@{
        source_status = $sourceStatus
        live_status = $liveStatus
        page_quality_status = $pageQualityStatus
        product_status = $productStatus
        product_reason = [string](Safe-Get -Object $productStatusDetail -Key 'reason' -Default 'none')
        repo_summary_status = $repoSummaryOut
        failure_stage = $failedStage
        error_message = $errorMessage
        failure_node = [string]$CurrentStage
        decision_build_failed_node = $decisionBuildFailedNode
        blocker = [string](Safe-Get -Object $Decision -Key 'core_problem' -Default '')
    }

    $targetValue = [string]$env:TARGET_REPO_PATH
    if ([string]::IsNullOrWhiteSpace($targetValue)) {
        $targetValue = [string](Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'base_url' -Default 'UNKNOWN_TARGET')
    }

    $steps = @(
        [ordered]@{ name = 'INPUT_VALIDATION'; status = if ($LastSuccessStage -in @('INPUT_VALIDATION', 'DECISION_BUILD', 'OPERATOR_OUTPUT_CONTRACT', 'COMPLETE')) { 'PASS' } else { 'UNKNOWN' } },
        [ordered]@{ name = 'DECISION_BUILD'; status = if ($LastSuccessStage -in @('DECISION_BUILD', 'OPERATOR_OUTPUT_CONTRACT', 'COMPLETE')) { 'PASS' } else { 'FAIL_OR_SKIPPED' } },
        [ordered]@{ name = 'OPERATOR_OUTPUT_CONTRACT'; status = if ($CurrentStage -eq 'COMPLETE' -or $LastSuccessStage -eq 'OPERATOR_OUTPUT_CONTRACT') { 'PASS' } else { 'FAIL_OR_SKIPPED' } }
    )
    $contract = [ordered]@{
        schema_version = '2.0'
        run_id = $runId
        started_at = $runStartedAt
        finished_at = $RunFinishedAt
        target_type = $ResolvedMode
        steps = $steps
        final_status = $FinalStatus
        failed_step = $failedStage
        error_class = if ([string]::IsNullOrWhiteSpace($errorMessage)) { '' } else { 'RUNTIME_FAILURE' }
        message = if ([string]::IsNullOrWhiteSpace($errorMessage)) { $executiveSummary } else { $errorMessage }
        run_status = [ordered]@{
            run_id = $runId
            target = $targetValue
            mode = $ResolvedMode
            started_at = $runStartedAt
            finished_at = $RunFinishedAt
            final_status = $FinalStatus
            final_stage = $CurrentStage
            last_success_stage = $LastSuccessStage
        }
        executive_summary = $executiveSummary
        key_evidence_excerpts = $evidence
        repair_hint = $repairHint
        artifact_manifest_summary = [ordered]@{
            artifacts = @($artifactItems)
            primary_truth_sources = @($primaryTruth)
        }
        next_technical_move = $nextMove
    }

    $manifestPath = Join-Path $reportsDir 'ARTIFACT_MANIFEST.json'
    Write-JsonFile -Path $manifestPath -Data ([ordered]@{
        run_id = $runId
        generated_at = $RunFinishedAt
        final_status = $FinalStatus
        artifacts = @($artifactItems)
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
        decision_build_failed_node = $decisionBuildFailedNode
        confirmed_passing_stages = @($confirmedPassingStages)
        usable_partial_artifacts_exist = [bool]$usablePartialArtifacts
        next_technical_move = $nextMove
        key_evidence_excerpts = $evidence
        primary_truth_sources = @($primaryTruth)
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
        "- source_status: $($evidence.source_status)",
        "- live_status: $($evidence.live_status)",
        "- page_quality_status: $($evidence.page_quality_status)",
        "- product_status: $($evidence.product_status)",
        "- product_reason: $($evidence.product_reason)",
        "- repo_summary_status: $($evidence.repo_summary_status)",
        "- failure_stage: $($evidence.failure_stage)",
        "- failure_node: $($evidence.failure_node)",
        "- decision_build_failed_node: $($evidence.decision_build_failed_node)",
        "- blocker: $($evidence.blocker)",
        "- error_message: $($evidence.error_message)",
        '',
        'REPAIR HINT',
        "- target_file: $([string](Safe-Get -Object $repairHint -Key 'target_file' -Default 'agents/gh_batch/site_auditor_cloud/agent.ps1'))",
        "- broken_block: $([string](Safe-Get -Object $repairHint -Key 'broken_block' -Default 'UNKNOWN'))",
        "- next_action: $([string](Safe-Get -Object $repairHint -Key 'next_action' -Default $nextMove))",
        "- priority_routes: $((@(Safe-Get -Object $repairHint -Key 'priority_routes' -Default @()) -join ', '))",
        '',
        'ARTIFACT MANIFEST SUMMARY'
    )

    foreach ($artifact in @($artifactItems | Sort-Object -Property @{Expression='priority_for_operator';Descending=$false}, @{Expression='path';Descending=$false})) {
        $lines += "- $($artifact.path) | type=$($artifact.artifact_type) | priority=$($artifact.priority_for_operator) | purpose=$($artifact.purpose)"
    }

    $lines += ''
    $lines += 'PRIMARY TRUTH SOURCES'
    foreach ($truth in @($primaryTruth)) {
        $lines += "- $truth"
    }

    if ($FinalStatus -in @('FAIL', 'PARTIAL')) {
        $lines += ''
        $lines += 'FAILURE SUMMARY'
        $lines += "- exact_failed_stage_or_node: $failedStage"
        $lines += "- error_class_or_message: $($evidence.error_message)"
        $lines += "- confirmed_passing_stages: $((@($confirmedPassingStages) -join ', '))"
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

    $AuditResult['product_status'] = [string]$productStatusText
    $AuditResult['product_status_detail'] = $productStatusDetail
    $AuditResult['product_closeout'] = $productCloseout
    $liveSummary = Convert-ToHashtableSafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'summary' -Default @{})
    $routeDetailsForCoverage = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'route_details' -Default @())
    $visualCoverage = Convert-ToHashtableSafe -Value (Safe-Get -Object $liveSummary -Key 'visual_coverage' -Default @{})
    if (@($visualCoverage.Keys).Count -eq 0) {
        $routesTotalLocal = [int]@($routeDetailsForCoverage).Count
        $routesCapturedLocal = [int]@($routeDetailsForCoverage | Where-Object { [int](Safe-Get -Object $_ -Key 'screenshotCount' -Default 0) -ge 3 }).Count
        $coverageScoreLocal = if ($routesTotalLocal -gt 0) { [int][Math]::Round((($routesCapturedLocal / [double]$routesTotalLocal) * 100), 0) } else { 0 }
        $visualCoverage = [ordered]@{
            routes_total = $routesTotalLocal
            routes_captured = $routesCapturedLocal
            issue_screenshots = [int](Safe-Get -Object $liveSummary -Key 'issue_screenshots' -Default 0)
            coverage_score = $coverageScoreLocal
        }
    }
    $decisionStage = [string](Safe-Get -Object $Decision -Key 'stage' -Default 'BROKEN')
    $decisionCore = [string](Safe-Get -Object $Decision -Key 'core_problem' -Default 'Decision core problem was not generated.')
    $decisionP0 = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'p0' -Default @())
    $doNextNow = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next_now' -Default (Safe-Get -Object $Decision -Key 'do_next' -Default @()))
    $doNextAfter = Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next_after' -Default @())
    $validatorPass = ($FinalStatus -ne 'FAIL')
    $AuditResult['schema_version'] = '4.0'
    $AuditResult['run_id'] = $runId
    $AuditResult['target'] = if ([string]::IsNullOrWhiteSpace([string]$env:TARGET_REPO_PATH)) { [string]$env:BASE_URL } else { [string]$env:TARGET_REPO_PATH }
    $AuditResult['runtime'] = [ordered]@{
        status = $FinalStatus
        validator_pass = [bool]$validatorPass
        final_output_contract_pass = $false
        diagnostic_or_result_present = $false
    }
    $decisionRepairHint = Convert-ToHashtableSafe -Value (Safe-Get -Object $Decision -Key 'repair_hint' -Default @{})
    $decisionPriorityRoutes = Convert-ToStringArraySafe -Value (Safe-Get -Object $Decision -Key 'priority_routes' -Default @())
    $AuditResult['decision'] = [ordered]@{
        stage = [string]$decisionStage
        core_problem = (($decisionCore -replace "`r", ' ') -replace "`n", ' ').Trim()
        p0 = @($decisionP0 | Select-Object -Unique)
        do_next = [ordered]@{
            now = @($doNextNow | Select-Object -Unique)
            after = @($doNextAfter | Select-Object -Unique)
        }
        repair_hint = $decisionRepairHint
        priority_routes = @($decisionPriorityRoutes)
    }
    $routeDetailsForVisualTruth = Convert-ToObjectArraySafe -Value (Safe-Get -Object (Safe-Get -Object $AuditResult -Key 'live' -Default @{}) -Key 'route_details' -Default @())
    $visualManifestPath = Join-Path $reportsDir 'visual_manifest.json'
    $packagedScreenshotDir = Join-Path $reportsDir 'screenshots'
    $capturedScreenshotCount = 0
    if (Test-Path -Path $packagedScreenshotDir -PathType Container) {
        $capturedScreenshotCount = @(Get-ChildItem -Path $packagedScreenshotDir -Filter '*.png' -File -Recurse -ErrorAction SilentlyContinue).Count
    }
    if ($capturedScreenshotCount -le 0) {
        foreach ($routeItem in @($routeDetailsForVisualTruth)) {
            $capturedScreenshotCount += [int](Safe-Get -Object $routeItem -Key 'screenshotCount' -Default 0)
        }
    }
    $visualAuditActive = ((Test-Path -Path $visualManifestPath -PathType Leaf) -or ($capturedScreenshotCount -gt 0) -or (@($routeDetailsForVisualTruth).Count -gt 0))
    $visualCoverage['visual_audit_active'] = [bool]$visualAuditActive
    $visualCoverage['screenshots_packaged'] = [int]$capturedScreenshotCount
    $visualCoverage['routes_with_evidence'] = [int]@($routeDetailsForVisualTruth | Where-Object { [int](Safe-Get -Object $_ -Key 'screenshotCount' -Default 0) -gt 0 }).Count
    $AuditResult['visual_coverage'] = $visualCoverage
    $AuditResult['facts'] = [ordered]@{
        mode = $ResolvedMode
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
    if ((Normalize-ToArray $topIssues).Count -eq 0) { $topIssues = @($decisionP2) }
    if ((Normalize-ToArray $topIssues).Count -eq 0) { $topIssues = @('No major issues detected from collected source/live evidence.') }

    $priorityActions = New-Object System.Collections.Generic.List[string]
    $doNextItems = Normalize-ToArray @((Normalize-ToArray (Safe-Get -Object $Decision -Key 'next_actions' -Default (Safe-Get -Object $Decision -Key 'do_next' -Default @()))) | Select-Object -First 3)
    if ((Normalize-ToArray $doNextItems).Count -gt 0) {
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
    $requiredInputsLine = if ($requiredInputs.Count -gt 0) { $requiredInputs -join ', ' } else { 'Not required for this mode.' }
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
    $criticalBlockers = Convert-ToObjectArrayOrEmpty -Value @($decisionP0 | Select-Object -First 3)
    if ($criticalBlockers.Count -eq 0) { $criticalBlockers = @('No critical blockers were detected; execute operator path to validate baseline stability.') }
    $doNextItems = Convert-ToObjectArrayOrEmpty -Value @((Convert-ToObjectArrayOrEmpty -Value (Safe-Get -Object $Decision -Key 'do_next' -Default @())) | Select-Object -First 3)
    if ($doNextItems.Count -eq 0) { $doNextItems = @('Execute remediation package steps from reports/REMEDIATION_PACKAGE.json and rerun SITE_AUDITOR.') }
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
    for ($i = 0; $i -lt $criticalBlockers.Count; $i++) {
        $item = $criticalBlockers[$i]
        $reportLines += "- WHAT: $item"
        $reportLines += "- ORDER: $($i + 1)"
        $reportLines += '- WHY: This condition blocks reliable operator execution or baseline quality.'
        $reportLines += '- IMPACT: Shipping without this fix risks false confidence and repeat audit failures.'
    }
    $reportLines += ''
    $reportLines += 'SECTION: OPERATOR PATH'
    for ($i = 0; $i -lt $doNextItems.Count; $i++) {
        $reportLines += "STEP $($i + 1) -> $($doNextItems[$i])"
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

    $manifest = @{
        mode = $ResolvedMode
        status = $FinalStatus
        repo_root = $repoRoot
        target_repo_bound = $sourceEnabled
        output_root = $base
        report_files = @($reportFiles)
        run_id = $runId
        started_at = $runStartedAt
        finished_at = $RunFinishedAt
        final_stage = $CurrentStage
        last_success_stage = $LastSuccessStage
        timestamp = $timestamp
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


    $runReportJsonPath = Join-Path $reportsDir 'RUN_REPORT.json'
    if (-not (Test-Path $runReportJsonPath -PathType Leaf)) {
        $fallbackTruth = Get-FallbackTruthEvidence -AuditResultPath $auditResultPath -FailureReason $FailureReason -CurrentStage $currentStage -LastSuccessStage $lastSuccessStage
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
            key_evidence_excerpts = [ordered]@{
                source_status = [string](Safe-Get -Object $fallbackTruth -Key 'source_status' -Default 'UNKNOWN')
                live_status = [string](Safe-Get -Object $fallbackTruth -Key 'live_status' -Default 'UNKNOWN')
                page_quality_status = [string](Safe-Get -Object $fallbackTruth -Key 'page_quality_status' -Default 'NOT_EVALUATED')
                product_status = [string](Safe-Get -Object $fallbackTruth -Key 'product_status' -Default 'UNKNOWN')
                product_reason = [string](Safe-Get -Object $fallbackTruth -Key 'product_reason' -Default 'Fallback report only.')
                repo_summary_status = [string](Safe-Get -Object $fallbackTruth -Key 'repo_summary_status' -Default 'UNKNOWN')
                failure_stage = [string](Safe-Get -Object $fallbackTruth -Key 'failure_stage' -Default $currentStage)
                error_message = [string](Safe-Get -Object $fallbackTruth -Key 'error_message' -Default '')
                failure_node = [string](Safe-Get -Object $fallbackTruth -Key 'failure_node' -Default $currentStage)
                blocker = [string](Safe-Get -Object $fallbackTruth -Key 'blocker' -Default 'Unknown fallback failure.')
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
            error_message = if ([string]::IsNullOrWhiteSpace($FailureReason)) { '' } else { $FailureReason }
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
        if ($auditResultNode.decision -is [System.Collections.IDictionary] -and [string](Safe-Get -Object $auditResultNode.decision -Key 'stage' -Default '') -eq 'READY') {
            $auditResultNode.decision.stage = 'BROKEN'
            $auditResultNode.decision.core_problem = 'Final output contract is missing required artifacts; run is not READY.'
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

    $warningsForDecision = Convert-ToDecisionWarningStringArray -Value (Safe-Get -Object $liveLayer -Key 'warnings' -Default @())

    $lastSuccessStage = 'INPUT_VALIDATION'
    $currentStage = 'DECISION_BUILD'
    $decision = Build-DecisionLayer -ResolvedMode $resolvedMode -SourceLayer $sourceLayer -LiveLayer $liveLayer -MissingInputs @($missingInputs) -Warnings $warningsForDecision
    $lastSuccessStage = 'DECISION_BUILD'
    if ($liveLayer.enabled -and ($liveLayer.summary -is [System.Collections.IDictionary])) {
        $liveLayer.summary.contradiction_summary = Safe-Get -Object $decision -Key 'contradiction_summary' -Default @{}
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

    $failureReason = $global:AuditError.Exception.Message
    if (-not $failureReason) { $failureReason = 'Unknown failure while running SITE_AUDITOR.' }
    if ($null -ne $global:DecisionForensics) {
        $dfFunction = [string](Safe-Get -Object $global:DecisionForensics -Key 'function_name' -Default '')
        $dfOperation = [string](Safe-Get -Object $global:DecisionForensics -Key 'activeOperationLabel' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($dfFunction) -or -not [string]::IsNullOrWhiteSpace($dfOperation)) {
            $failureReason = "$failureReason [DECISION_BUILD/$dfFunction/$dfOperation]"
        }
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
