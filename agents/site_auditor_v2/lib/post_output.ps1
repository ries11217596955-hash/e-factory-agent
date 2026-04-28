
function Get-SafeProp {
    param($Obj, [string]$Name, $Default)
    if ($null -eq $Obj) { return $Default }
    if ($Obj.PSObject.Properties[$Name]) { return $Obj.$Name }
    return $Default
}
function Invoke-PostOutput {
    param(
        [string]$OutputDir,
        [string]$RunReportPath
    )

    if (-not (Test-Path $RunReportPath)) { return }

    $report = Get-Content $RunReportPath -Raw | ConvertFrom-Json

    $statusLabel = Get-SafeProp $report 'status_label' ''
$statusBase = Get-SafeProp $report 'status' ''
$status = if (-not [string]::IsNullOrWhiteSpace($statusLabel)) { [string]$statusLabel } else { [string]$statusBase }
    $omb = Get-SafeProp $report 'operator_memory_bridge' $null
$bridge = if ($omb -and $omb.PSObject.Properties['self_explanation']) { $omb.self_explanation } else { [pscustomobject]@{} }
    $agentInfo = (Get-SafeProp $bridge 'what_this_agent_is' '')
    $runInfo = (Get-SafeProp $bridge 'what_happened_in_this_run' '')
    $systemMap = @((Get-SafeProp $bridge 'system_map_minimal' ''))
    $nextStepRaw = [string](Get-SafeProp $bridge 'next_step_one_only' '')
    $forbidden = @((Get-SafeProp $bridge 'forbidden' ''))

    $checked = @(Get-SafeProp $runInfo 'checked_vs_not_checked' @())
    $verifiedLine = ($checked | Where-Object { $_ -match '(?i)checked|verified|did' } | Select-Object -First 1)
    if (-not $verifiedLine) { $verifiedLine = ($checked | Select-Object -First 1) }
    if (-not $verifiedLine) { $verifiedLine = 'No explicit verified scope line was provided in RUN_REPORT.' }

    $notVerifiedLine = ($checked | Where-Object { $_ -match '(?i)not|limit|coverage|not checked|did not' } | Select-Object -First 1)
    if (-not $notVerifiedLine) { $notVerifiedLine = 'No explicit non-verified scope line was provided in RUN_REPORT.' }

    $executedLayers = ($systemMap | Where-Object { $_ -notmatch '(?i)limit|limited' })
    $limitedLayers = ($systemMap | Where-Object { $_ -match '(?i)limit|limited' })
    $executedLine = if (@($executedLayers).Count -gt 0) { (@($executedLayers) -join '; ') } else { 'Execution layers were not explicitly listed.' }
    $limitedLine = if (@($limitedLayers).Count -gt 0) { (@($limitedLayers) -join '; ') } else { [string](Get-SafeProp $runInfo 'why_confidence' '') }
    $routesCount = [int]@(Get-SafeProp $report 'selected_routes' @()).Count
    $captureReport = Get-SafeProp $report 'capture_report' $null
    $screenshotsCount = if ($captureReport -and $captureReport.PSObject.Properties['captures_success']) { [int]$captureReport.captures_success } else { 0 }
    $layersExecutedCount = [int]@($executedLayers).Count
    $statusPlain = [string](Get-SafeProp $runInfo 'status_meaning_plain' '')
    if ([string]::IsNullOrWhiteSpace($statusPlain)) { $statusPlain = 'No plain status explanation was provided.' }
    $limitationLine = if ([string](Get-SafeProp $runInfo 'confidence' '') -eq 'LOW') { [string](Get-SafeProp $runInfo 'why_confidence' '') } else { 'none (confidence is not LOW in this run).' }
    $forbiddenTop = @($forbidden | Select-Object -First 3)
    if (@($forbiddenTop).Count -lt 2) {
        $forbiddenTop += @('do not refactor', 'do not add features', 'do not assume full audit')
        $forbiddenTop = @($forbiddenTop | Select-Object -Unique | Select-Object -First 3)
    }
    $systemLine = [string](Get-SafeProp $agentInfo 'universal_audit_engine' '')
    if ([string]::IsNullOrWhiteSpace($systemLine)) { $systemLine = 'SITE_AUDITOR_V2 runs bounded LINK evidence checks and outputs operator handoff artifacts.' }
    $nextStepReason = if ([string]::IsNullOrWhiteSpace($nextStepRaw)) { [string](Get-SafeProp $runInfo 'why_confidence' '') } else { $nextStepRaw }
    if ([string]::IsNullOrWhiteSpace($nextStepReason)) { $nextStepReason = 'this run is bounded to sampled LINK evidence and requires a truth-file anchored follow-up' }
    $nextStep = "Open RUN_REPORT.json and inspect operator_memory_bridge.next_operator_posture.what_to_inspect_next[0] because $nextStepReason"

    $en = @(
        '=== OPERATOR CONTROL ===',
        'STATUS:',
        ("$status - $statusPlain"),
        'WHAT WAS ACTUALLY CHECKED:',
        ("- routes count: $routesCount"),
        ("- screenshots count: $screenshotsCount"),
        ("- layers executed: $layersExecutedCount"),
        'LIMITATION:',
        ("- $limitationLine"),
        'NEXT STEP:',
        ("- $nextStep"),
        'DO NOT:',
        ("- " + ($forbiddenTop -join '; ')),
        'SYSTEM:',
        ("- $systemLine"),
        '========================',
        '',
        "SITE STATUS: $status",
        '',
        '1. WHAT THIS RUN MEANS',
        ("- Status: " + [string](Get-SafeProp $runInfo 'status' '')),
        ("- Plain meaning: " + [string](Get-SafeProp $runInfo 'status_meaning_plain' '')),
        ("- Verified in this run: " + $verifiedLine),
        ("- Not verified in this run: " + $notVerifiedLine),
        '',
        '2. SYSTEM STATE',
        ("- Layers executed: " + $executedLine),
        ("- Layers limited: " + $limitedLine),
        '',
        '3. KEY LIMITATION (ONE)',
        ("- " + [string](Get-SafeProp $runInfo 'why_confidence' '')),
        '',
        '4. NEXT STEP (ONE ONLY)',
        ("- " + $nextStep),
        '',
        '5. DO NOT DO'
    )
    foreach ($line in $forbidden) { $en += "- $line" }
    $en += @(
        '',
        '6. OPTIONAL: DETAILED FINDINGS',
        '',
        'DETAILS: WHAT THIS AGENT IS',
        ("- universal audit engine: " + [string](Get-SafeProp $agentInfo 'universal_audit_engine' '')),
        ("- current mode (LINK): " + [string](Get-SafeProp $agentInfo 'current_mode' '')),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @((Get-SafeProp $agentInfo 'run_scope' ''))) { $en += "- $line" }
    $en += @(
        '',
        'DETAILS: STATUS REFERENCE',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string](Get-SafeProp $runInfo 'confidence' '')),
        ("- why confidence is LOW or not: " + [string](Get-SafeProp $runInfo 'why_confidence' '')),
        '- checked vs not checked:'
    )
    $checkedVsNotCheckedEn = Get-SafeProp $runInfo 'checked_vs_not_checked' @()
    foreach ($line in @($checkedVsNotCheckedEn)) { $en += "- $line" }
    $en += @(
        '',
        'DETAILS: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $en += "- $line" }

    $ru = @(
        '=== OPERATOR CONTROL ===',
        'STATUS:',
        ("$status - $statusPlain"),
        'WHAT WAS ACTUALLY CHECKED:',
        ("- routes count: $routesCount"),
        ("- screenshots count: $screenshotsCount"),
        ("- layers executed: $layersExecutedCount"),
        'LIMITATION:',
        ("- $limitationLine"),
        'NEXT STEP:',
        ("- $nextStep"),
        'DO NOT:',
        ("- " + ($forbiddenTop -join '; ')),
        'SYSTEM:',
        ("- $systemLine"),
        '========================',
        '',
        "СТАТУС САЙТА: $status",
        '',
        '1. WHAT THIS RUN MEANS',
        ("- Status: " + [string](Get-SafeProp $runInfo 'status' '')),
        ("- Plain meaning: " + [string](Get-SafeProp $runInfo 'status_meaning_plain' '')),
        ("- Verified in this run: " + $verifiedLine),
        ("- Not verified in this run: " + $notVerifiedLine),
        '',
        '2. SYSTEM STATE',
        ("- Layers executed: " + $executedLine),
        ("- Layers limited: " + $limitedLine),
        '',
        '3. KEY LIMITATION (ONE)',
        ("- " + [string](Get-SafeProp $runInfo 'why_confidence' '')),
        '',
        '4. NEXT STEP (ONE ONLY)',
        ("- " + $nextStep),
        '',
        '5. DO NOT DO'
    )
    foreach ($line in $forbidden) { $ru += "- $line" }
    $ru += @(
        '',
        '6. OPTIONAL: DETAILED FINDINGS',
        '',
        'DETAILS: WHAT THIS AGENT IS',
        ("- universal audit engine: " + [string](Get-SafeProp $agentInfo 'universal_audit_engine' '')),
        ("- current mode (LINK): " + [string](Get-SafeProp $agentInfo 'current_mode' '')),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @((Get-SafeProp $agentInfo 'run_scope' ''))) { $ru += "- $line" }
    $ru += @(
        '',
        'DETAILS: STATUS REFERENCE',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string](Get-SafeProp $runInfo 'confidence' '')),
        ("- why confidence is LOW or not: " + [string](Get-SafeProp $runInfo 'why_confidence' '')),
        '- checked vs not checked:'
    )
    $checkedVsNotChecked = Get-SafeProp $runInfo 'checked_vs_not_checked' @()
    foreach ($line in @($checkedVsNotChecked)) { $ru += "- $line" }
    $ru += @(
        '',
        'DETAILS: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $ru += "- $line" }

    $en | Out-File (Join-Path $OutputDir "REPORT_EN.txt") -Encoding UTF8
    $ru | Out-File (Join-Path $OutputDir "REPORT_RU.txt") -Encoding UTF8

# --- CI CONTRACT EXPORT ---
$rootDir = "agents/site_auditor_v2"
Copy-Item (Join-Path $OutputDir "REPORT_EN.txt") (Join-Path $rootDir "REPORT_EN.txt") -Force
Copy-Item (Join-Path $OutputDir "REPORT_RU.txt") (Join-Path $rootDir "REPORT_RU.txt") -Force
Write-Host "POST_OUTPUT: ROOT_REPORT_EXPORT_DONE"
# --- END ---

}
