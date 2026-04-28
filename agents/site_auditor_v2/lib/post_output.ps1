function Invoke-PostOutput {
    param(
        [string]$OutputDir,
        [string]$RunReportPath
    )

    if (-not (Test-Path $RunReportPath)) { return }

    $report = Get-Content $RunReportPath -Raw | ConvertFrom-Json

    $status = if ($report.status_label) { [string]$report.status_label } else { [string]$report.status }
    $bridge = $report.operator_memory_bridge.self_explanation
    $agentInfo = $bridge.what_this_agent_is
    $runInfo = $bridge.what_happened_in_this_run
    $systemMap = @($bridge.system_map_minimal)
    $nextStep = [string]$bridge.next_step_one_only
    $forbidden = @($bridge.forbidden)

    $checked = @($runInfo.checked_vs_not_checked)
    $verifiedLine = ($checked | Where-Object { $_ -match '(?i)checked|verified|did' } | Select-Object -First 1)
    if (-not $verifiedLine) { $verifiedLine = ($checked | Select-Object -First 1) }
    if (-not $verifiedLine) { $verifiedLine = 'No explicit verified scope line was provided in RUN_REPORT.' }

    $notVerifiedLine = ($checked | Where-Object { $_ -match '(?i)not|limit|coverage|not checked|did not' } | Select-Object -First 1)
    if (-not $notVerifiedLine) { $notVerifiedLine = 'No explicit non-verified scope line was provided in RUN_REPORT.' }

    $executedLayers = ($systemMap | Where-Object { $_ -notmatch '(?i)limit|limited' })
    $limitedLayers = ($systemMap | Where-Object { $_ -match '(?i)limit|limited' })
    $executedLine = if ($executedLayers.Count -gt 0) { ($executedLayers -join '; ') } else { 'Execution layers were not explicitly listed.' }
    $limitedLine = if ($limitedLayers.Count -gt 0) { ($limitedLayers -join '; ') } else { [string]$runInfo.why_confidence }

    $en = @(
        "SITE STATUS: $status",
        '',
        '1. WHAT THIS RUN MEANS',
        ("- Status: " + [string]$runInfo.status),
        ("- Plain meaning: " + [string]$runInfo.status_meaning_plain),
        ("- Verified in this run: " + $verifiedLine),
        ("- Not verified in this run: " + $notVerifiedLine),
        '',
        '2. SYSTEM STATE',
        ("- Layers executed: " + $executedLine),
        ("- Layers limited: " + $limitedLine),
        '',
        '3. KEY LIMITATION (ONE)',
        ("- " + [string]$runInfo.why_confidence),
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
        ("- universal audit engine: " + [string]$agentInfo.universal_audit_engine),
        ("- current mode (LINK): " + [string]$agentInfo.current_mode),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @($agentInfo.run_scope)) { $en += "- $line" }
    $en += @(
        '',
        'DETAILS: STATUS REFERENCE',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string]$runInfo.confidence),
        ("- why confidence is LOW or not: " + [string]$runInfo.why_confidence),
        '- checked vs not checked:'
    )
    foreach ($line in @($runInfo.checked_vs_not_checked)) { $en += "- $line" }
    $en += @(
        '',
        'DETAILS: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $en += "- $line" }

    $ru = @(
        "СТАТУС САЙТА: $status",
        '',
        '1. WHAT THIS RUN MEANS',
        ("- Status: " + [string]$runInfo.status),
        ("- Plain meaning: " + [string]$runInfo.status_meaning_plain),
        ("- Verified in this run: " + $verifiedLine),
        ("- Not verified in this run: " + $notVerifiedLine),
        '',
        '2. SYSTEM STATE',
        ("- Layers executed: " + $executedLine),
        ("- Layers limited: " + $limitedLine),
        '',
        '3. KEY LIMITATION (ONE)',
        ("- " + [string]$runInfo.why_confidence),
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
        ("- universal audit engine: " + [string]$agentInfo.universal_audit_engine),
        ("- current mode (LINK): " + [string]$agentInfo.current_mode),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @($agentInfo.run_scope)) { $ru += "- $line" }
    $ru += @(
        '',
        'DETAILS: STATUS REFERENCE',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string]$runInfo.confidence),
        ("- why confidence is LOW or not: " + [string]$runInfo.why_confidence),
        '- checked vs not checked:'
    )
    foreach ($line in @($runInfo.checked_vs_not_checked)) { $ru += "- $line" }
    $ru += @(
        '',
        'DETAILS: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $ru += "- $line" }

    $en | Out-File (Join-Path $OutputDir "REPORT_EN.txt") -Encoding UTF8
    $ru | Out-File (Join-Path $OutputDir "REPORT_RU.txt") -Encoding UTF8
}
