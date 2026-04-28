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

    $en = @(
        "SITE STATUS: $status",
        '',
        'SECTION: WHAT THIS AGENT IS',
        ("- universal audit engine: " + [string]$agentInfo.universal_audit_engine),
        ("- current mode (LINK): " + [string]$agentInfo.current_mode),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @($agentInfo.run_scope)) { $en += "- $line" }
    $en += @(
        '',
        'SECTION: WHAT HAPPENED IN THIS RUN',
        ("- status: " + [string]$runInfo.status),
        ("- plain meaning: " + [string]$runInfo.status_meaning_plain),
        '- PASS / PASS_WITH_LIMITS / FAIL meaning in plain language:',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string]$runInfo.confidence),
        ("- why confidence is LOW or not: " + [string]$runInfo.why_confidence),
        '- what was actually checked vs not checked:'
    )
    foreach ($line in @($runInfo.checked_vs_not_checked)) { $en += "- $line" }
    $en += @(
        '',
        'SECTION: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $en += "- $line" }
    $en += @(
        '',
        'SECTION: NEXT STEP (ONE ONLY)',
        ("- " + $nextStep),
        '',
        'SECTION: FORBIDDEN'
    )
    foreach ($line in $forbidden) { $en += "- $line" }

    $ru = @(
        "СТАТУС САЙТА: $status",
        '',
        'SECTION: WHAT THIS AGENT IS',
        ("- universal audit engine: " + [string]$agentInfo.universal_audit_engine),
        ("- current mode (LINK): " + [string]$agentInfo.current_mode),
        '- what this run actually did (routes, screenshots, limits):'
    )
    foreach ($line in @($agentInfo.run_scope)) { $ru += "- $line" }
    $ru += @(
        '',
        'SECTION: WHAT HAPPENED IN THIS RUN',
        ("- status: " + [string]$runInfo.status),
        ("- plain meaning: " + [string]$runInfo.status_meaning_plain),
        '- PASS / PASS_WITH_LIMITS / FAIL meaning in plain language:',
        '- PASS = sampled run found no material defects; not a full-site guarantee.',
        '- PASS_WITH_LIMITS = run finished but confidence/coverage limits block full-site claims.',
        '- FAIL = defects or evidence gaps require operator action before trusting the outcome.',
        ("- confidence: " + [string]$runInfo.confidence),
        ("- why confidence is LOW or not: " + [string]$runInfo.why_confidence),
        '- what was actually checked vs not checked:'
    )
    foreach ($line in @($runInfo.checked_vs_not_checked)) { $ru += "- $line" }
    $ru += @(
        '',
        'SECTION: SYSTEM MAP (MINIMAL)'
    )
    foreach ($line in $systemMap) { $ru += "- $line" }
    $ru += @(
        '',
        'SECTION: NEXT STEP (ONE ONLY)',
        ("- " + $nextStep),
        '',
        'SECTION: FORBIDDEN'
    )
    foreach ($line in $forbidden) { $ru += "- $line" }

    $en | Out-File (Join-Path $OutputDir "REPORT_EN.txt") -Encoding UTF8
    $ru | Out-File (Join-Path $OutputDir "REPORT_RU.txt") -Encoding UTF8
}
