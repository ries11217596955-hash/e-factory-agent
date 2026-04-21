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

    $global:RouteNormalizationAggregateTrace = @($global:RouteNormalizationAggregateTrace)
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
