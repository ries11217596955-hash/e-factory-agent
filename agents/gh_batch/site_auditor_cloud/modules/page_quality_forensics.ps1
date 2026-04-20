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
