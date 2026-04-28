function Invoke-PostOutput {
    param(
        [string]$OutputDir,
        [string]$RunReportPath
    )

    if (-not (Test-Path $RunReportPath)) { return }

    $report = Get-Content $RunReportPath -Raw | ConvertFrom-Json

    $status = if ($report.status_label) { [string]$report.status_label } else { [string]$report.status }
    $agentName = 'SITE_AUDITOR_V2'
    $productScope = if ($report.operator_memory_bridge.identity_anchor.what_system_is_being_built) { [string]$report.operator_memory_bridge.identity_anchor.what_system_is_being_built } else { 'site audit evidence system' }
    $executionMode = if ($report.execution_report.mode) { [string]$report.execution_report.mode } else { 'LINK' }
    $currentLayer = 'REPORT_LAYER'
    $responsibilityMap = @(
        'agent.ps1 -> orchestrator and stage control',
        'modules/stage_link_fetch.ps1 -> LINK fetch and route discovery',
        'modules/stage_capture_reconciliation.ps1 -> evidence reconciliation',
        'modules/report_layer.ps1 -> findings synthesis and operator memory bridge',
        'lib/post_output.ps1 -> human report handoff text'
    )

    $passWithLimitsMeaningEn = 'PASS_WITH_LIMITS means the run completed but confidence/scope constraints still block full-site claims.'
    $passWithLimitsMeaningRu = 'PASS_WITH_LIMITS означает: запуск завершён, но ограничения уверенности/охвата не позволяют делать вывод о всём сайте.'

    $inspectNext = @($report.operator_memory_bridge.next_operator_posture.what_to_inspect_next)
    $recommendedMove = if ($report.operator_memory_bridge.next_operator_posture.next_system_move) { [string]$report.operator_memory_bridge.next_operator_posture.next_system_move } else { [string]$report.next_step }
    $forbiddenMoves = @($report.forbidden_next_steps)
    if ($forbiddenMoves.Count -eq 0) { $forbiddenMoves = @($report.operator_memory_bridge.next_operator_posture.forbidden_drifts) }

    $runSummary = if ($report.summary) { [string]$report.summary } else { 'Run completed with bounded LINK evidence.' }

    $en = @(
        "SITE STATUS: $status",
        "WHAT THE AGENT IS: $agentName",
        "ACTIVE PRODUCT SCOPE: $productScope",
        "CURRENT EXECUTION MODE: $executionMode",
        "CURRENT LAYER: $currentLayer",
        'MODULE / FILE RESPONSIBILITY MAP:'
    )
    foreach ($line in $responsibilityMap) { $en += "- $line" }
    $en += @(
        "WHAT HAPPENED IN THIS RUN: $runSummary",
        ("PASS_WITH_LIMITS MEANING: " + $passWithLimitsMeaningEn),
        'WHAT TO INSPECT NEXT:'
    )
    foreach ($line in $inspectNext) { $en += "- $line" }
    $en += @(
        "ONE RECOMMENDED NEXT MOVE: $recommendedMove",
        'FORBIDDEN NEXT MOVES:'
    )
    foreach ($line in $forbiddenMoves) { $en += "- $line" }

    $ru = @(
        "СТАТУС САЙТА: $status",
        "ЧТО ЭТО ЗА АГЕНТ: $agentName",
        "АКТИВНЫЙ ПРОДУКТОВЫЙ КОНТУР: $productScope",
        "ТЕКУЩИЙ РЕЖИМ ВЫПОЛНЕНИЯ: $executionMode",
        "ТЕКУЩИЙ СЛОЙ: $currentLayer",
        'КАРТА ОТВЕТСТВЕННОСТИ МОДУЛЕЙ/ФАЙЛОВ:'
    )
    foreach ($line in $responsibilityMap) { $ru += "- $line" }
    $ru += @(
        "ЧТО ПРОИЗОШЛО В ЭТОМ ЗАПУСКЕ: $runSummary",
        ("СМЫСЛ PASS_WITH_LIMITS: " + $passWithLimitsMeaningRu),
        'ЧТО ПРОВЕРИТЬ ДАЛЬШЕ:'
    )
    foreach ($line in $inspectNext) { $ru += "- $line" }
    $ru += @(
        "ОДИН РЕКОМЕНДУЕМЫЙ СЛЕДУЮЩИЙ ШАГ: $recommendedMove",
        'ЗАПРЕЩЁННЫЕ СЛЕДУЮЩИЕ ДЕЙСТВИЯ:'
    )
    foreach ($line in $forbiddenMoves) { $ru += "- $line" }

    $en | Out-File (Join-Path $OutputDir "REPORT_EN.txt") -Encoding UTF8
    $ru | Out-File (Join-Path $OutputDir "REPORT_RU.txt") -Encoding UTF8
}
