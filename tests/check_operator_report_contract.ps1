[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required artifact missing: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Read-TextLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required artifact missing: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    return @($raw -split "`r?`n")
}

function Get-BlockLineIndex {
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ([string]$Lines[$i] -match $Pattern) {
            return $i
        }
    }

    return -1
}

$runReportPath = Join-Path $OutputFolder 'RUN_REPORT.json'
$reportEnPath = Join-Path $OutputFolder 'REPORT_EN.txt'
$reportRuPath = Join-Path $OutputFolder 'REPORT_RU.txt'

$runReport = Read-JsonFile -Path $runReportPath
$reportEnLines = Read-TextLines -Path $reportEnPath
$reportRuLines = Read-TextLines -Path $reportRuPath

$violations = [System.Collections.Generic.List[object]]::new()

function Add-Violation {
    param(
        [string]$Artifact,
        [string]$Field,
        [string]$Reason,
        [string]$Value = ''
    )

    $violations.Add([ordered]@{
        artifact_path = $Artifact
        field_path = $Field
        reason = $Reason
        offending_value = $Value
    })
}

function Test-OperatorControlBlock {
    param(
        [string]$Artifact,
        [string[]]$Lines,
        [string]$Status
    )

    $requiredHeadings = @(
        'STATUS:',
        'WHAT WAS ACTUALLY CHECKED:',
        'LIMITATION:',
        'NEXT STEP:',
        'DO NOT:',
        'SYSTEM:'
    )

    $blockStart = Get-BlockLineIndex -Lines $Lines -Pattern '^=== OPERATOR CONTROL ===$'
    if ($blockStart -lt 0) {
        Add-Violation -Artifact $Artifact -Field 'OPERATOR CONTROL' -Reason 'missing OPERATOR CONTROL block'
        return
    }

    if ($blockStart -gt 25) {
        Add-Violation -Artifact $Artifact -Field 'OPERATOR CONTROL' -Reason 'OPERATOR CONTROL block must be near top' -Value ([string]$blockStart)
    }

    $blockEnd = -1
    for ($i = $blockStart + 1; $i -lt $Lines.Count; $i++) {
        if ([string]$Lines[$i] -eq '========================') {
            $blockEnd = $i
            break
        }
    }
    if ($blockEnd -lt 0) { $blockEnd = [Math]::Min($Lines.Count - 1, $blockStart + 40) }

    $blockLines = @($Lines[$blockStart..$blockEnd])
    foreach ($heading in $requiredHeadings) {
        if ($blockLines -notcontains $heading) {
            Add-Violation -Artifact $Artifact -Field $heading -Reason 'missing required OPERATOR CONTROL field'
        }
    }

    $nextStepIndex = Get-BlockLineIndex -Lines $blockLines -Pattern '^NEXT STEP:$'
    if ($nextStepIndex -ge 0) {
        $nextStepValue = if (($nextStepIndex + 1) -lt $blockLines.Count) { [string]$blockLines[$nextStepIndex + 1] } else { '' }
        if ([string]::IsNullOrWhiteSpace($nextStepValue) -or $nextStepValue.Trim() -eq '-') {
            Add-Violation -Artifact $Artifact -Field 'NEXT STEP' -Reason 'NEXT STEP value is empty' -Value $nextStepValue
        }
    }

    if ($Status -eq 'PASS_WITH_LIMITS') {
        $limitIndex = Get-BlockLineIndex -Lines $blockLines -Pattern '^LIMITATION:$'
        $limitValue = if ($limitIndex -ge 0 -and ($limitIndex + 1) -lt $blockLines.Count) { [string]$blockLines[$limitIndex + 1] } else { '' }
        if ([string]::IsNullOrWhiteSpace($limitValue) -or $limitValue -match '(?i)none' -or $limitValue -match '(?i)not LOW') {
            Add-Violation -Artifact $Artifact -Field 'LIMITATION' -Reason 'PASS_WITH_LIMITS requires a real limitation explanation' -Value $limitValue
        }
    }
}

$statusLabel = if ($runReport.PSObject.Properties['status_label'] -and -not [string]::IsNullOrWhiteSpace([string]$runReport.status_label)) { [string]$runReport.status_label } else { [string]$runReport.status }
$bridge = $runReport.operator_memory_bridge
if ($null -eq $bridge) {
    Add-Violation -Artifact 'RUN_REPORT.json' -Field 'operator_memory_bridge' -Reason 'operator_memory_bridge is required'
}
else {
    $requiredBridgeFields = @('status_detail', 'current_execution_mode', 'current_layer', 'one_next_step', 'forbidden_next_steps')
    foreach ($field in $requiredBridgeFields) {
        $prop = $bridge.PSObject.Properties[$field]
        if ($null -eq $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            if ($field -eq 'forbidden_next_steps') {
                $items = if ($null -ne $prop) { @($prop.Value) } else { @() }
                if ($items.Count -eq 0) {
                    Add-Violation -Artifact 'RUN_REPORT.json' -Field ("operator_memory_bridge.$field") -Reason 'required bridge field missing or empty'
                }
            }
            else {
                Add-Violation -Artifact 'RUN_REPORT.json' -Field ("operator_memory_bridge.$field") -Reason 'required bridge field missing or empty'
            }
        }
    }

    $toolRecommendation = if ($bridge.PSObject.Properties['tool_recommendation']) { [string]$bridge.tool_recommendation } else { '' }
    $toolHint = if ($bridge.PSObject.Properties['tool_hint']) { [string]$bridge.tool_hint } else { '' }
    if ([string]::IsNullOrWhiteSpace($toolRecommendation) -and [string]::IsNullOrWhiteSpace($toolHint)) {
        Add-Violation -Artifact 'RUN_REPORT.json' -Field 'operator_memory_bridge.tool_recommendation|tool_hint' -Reason 'must provide tool_recommendation or tool_hint'
    }
}

Test-OperatorControlBlock -Artifact 'REPORT_EN.txt' -Lines $reportEnLines -Status $statusLabel
Test-OperatorControlBlock -Artifact 'REPORT_RU.txt' -Lines $reportRuLines -Status $statusLabel

if ($violations.Count -gt 0) {
    Write-Host 'OPERATOR_REPORT_CONTRACT_BREACH'
    $violations | ConvertTo-Json -Depth 10 | Write-Host
    exit 1
}

Write-Host 'OPERATOR_REPORT_CONTRACT_OK'
exit 0
